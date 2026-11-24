/// User management (administrators only).
module uim.myfiori.application.usecases.userusecases;

import std.algorithm : canFind, count, filter, sort;
import std.array : array;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class UserInteractor : UserUseCase {
    private UserRepository users;
    private PasswordHasher hasher;
    private Clock clock;
    private IdGenerator ids;
    private EventPublisher events;
    private DtoMapper mapper;

    this(UserRepository users, PasswordHasher hasher, Clock clock, IdGenerator ids, EventPublisher events,
        DtoMapper mapper) {
        this.users = users;
        this.hasher = hasher;
        this.clock = clock;
        this.ids = ids;
        this.events = events;
        this.mapper = mapper;
    }

    Page!UserDto list(in Principal p, PageRequest page) {
        AccessPolicy.requireAdmin(p);
        auto f = page.filter.strip.toLower;
        auto all = users.all().filter!(u => f.length == 0 || u.username.canFind(f)
                || u.displayName.toLower.canFind(f) || u.email.toLower.canFind(f)).array;
        all.sort!((a, b) => a.username < b.username);
        Page!UserDto r;
        r.total = all.length;
        const now = clock.now;
        foreach (u; slicePage(all, page.skip, page.top))
            r.items ~= mapper.user(u, now);
        return r;
    }

    UserDto get(in Principal p, string id) {
        if (p.userId != id)
            AccessPolicy.requireAdmin(p);
        return mapper.user(require(id), clock.now);
    }

    UserDto create(in Principal p, UserInput input) {
        AccessPolicy.requireAdmin(p);
        if (input.username.isNull)
            throw new ValidationException("User name is required");
        auto name = validUsername(input.username.get);
        if (users.byUsername(name) !is null)
            throw new ConflictException("User name already exists: " ~ name);
        if (input.password.isNull || input.password.get.length == 0)
            throw new ValidationException("Initial password is required");
        checkPasswordPolicy(input.password.get);
        const now = clock.now;
        auto u = new User;
        u.id = ids.newId;
        u.username = name;
        u.displayName = input.displayName.isNull ? name : input.displayName.get.strip;
        u.email = input.email.isNull ? "" : validEmail(input.email.get);
        u.role = parseRole(input.role.isNull ? "reader" : input.role.get);
        u.active = input.active.isNull ? true : input.active.get;
        u.passwordHash = hasher.hash(input.password.get);
        u.mustChangePassword = input.mustChangePassword.isNull ? true : input.mustChangePassword.get;
        u.createdAt = u.updatedAt = now;
        users.save(u);
        events.publish(DomainEvent("user.created", u.id, p.userId, u.username, now));
        return mapper.user(u, now);
    }

    UserDto update(in Principal p, string id, UserInput input) {
        AccessPolicy.requireAdmin(p);
        auto u = require(id);
        if (!input.username.isNull) {
            auto name = validUsername(input.username.get);
            auto other = users.byUsername(name);
            if (other !is null && other.id != u.id)
                throw new ConflictException("User name already exists: " ~ name);
            u.username = name;
        }
        if (!input.displayName.isNull)
            u.displayName = input.displayName.get.strip;
        if (!input.email.isNull)
            u.email = validEmail(input.email.get);
        if (!input.role.isNull) {
            auto role = parseRole(input.role.get);
            if (u.role == Role.admin && role != Role.admin)
                ensureAnotherAdmin(u.id);
            u.role = role;
        }
        if (!input.active.isNull) {
            if (!input.active.get) {
                if (u.id == p.userId)
                    throw new ValidationException("You cannot deactivate yourself");
                if (u.role == Role.admin)
                    ensureAnotherAdmin(u.id);
            }
            u.active = input.active.get;
        }
        if (!input.password.isNull && input.password.get.length) {
            checkPasswordPolicy(input.password.get);
            u.passwordHash = hasher.hash(input.password.get);
        }
        if (!input.mustChangePassword.isNull)
            u.mustChangePassword = input.mustChangePassword.get;
        u.updatedAt = clock.now;
        u.version_++;
        users.save(u);
        events.publish(DomainEvent("user.updated", u.id, p.userId, u.username, clock.now));
        return mapper.user(u, clock.now);
    }

    void resetPassword(in Principal p, string id, string newPassword) {
        AccessPolicy.requireAdmin(p);
        auto u = require(id);
        if (u.externalId.length && u.passwordHash.length == 0)
            throw new ValidationException("Externally managed users have no local password");
        checkPasswordPolicy(newPassword);
        u.passwordHash = hasher.hash(newPassword);
        u.mustChangePassword = true;
        u.failedLogins = 0;
        u.lockedUntil = u.lockedUntil.init;
        u.updatedAt = clock.now;
        u.version_++;
        users.save(u);
        events.publish(DomainEvent("user.password-reset", u.id, p.userId, u.username, clock.now));
    }

    void unlock(in Principal p, string id) {
        AccessPolicy.requireAdmin(p);
        auto u = require(id);
        u.failedLogins = 0;
        u.lockedUntil = u.lockedUntil.init;
        u.updatedAt = clock.now;
        users.save(u);
    }

    void remove(in Principal p, string id) {
        AccessPolicy.requireAdmin(p);
        auto u = require(id);
        if (u.id == p.userId)
            throw new ValidationException("You cannot delete yourself");
        if (u.role == Role.admin)
            ensureAnotherAdmin(u.id);
        users.remove(u.id);
        events.publish(DomainEvent("user.deleted", u.id, p.userId, u.username, clock.now));
    }

    private User require(string id) {
        auto u = users.byId(id);
        if (u is null)
            throw new NotFoundException("User not found");
        return u;
    }

    private static Role parseRole(string s) {
        Role r;
        if (!tryParseRole(s, r))
            throw new ValidationException("Unknown role '" ~ s ~ "' (reader, editor, admin)");
        return r;
    }

    private void ensureAnotherAdmin(string exceptId) {
        if (!users.all().canFind!(u => u.id != exceptId && u.role == Role.admin && u.active))
            throw new ConflictException("At least one active administrator is required");
    }
}
