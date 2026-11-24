/// Login, own profile and password change.
module uim.myfiori.application.usecases.authusecases;

import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class AuthInteractor : AuthUseCase {
    private UserRepository users;
    private PasswordHasher hasher;
    private TokenIssuer tokens;
    private Clock clock;
    private EventPublisher events;
    private DtoMapper mapper;
    private AccessResolver resolver;
    private string dummyHash; // constant-time behaviour for unknown users

    this(UserRepository users, PasswordHasher hasher, TokenIssuer tokens, Clock clock, EventPublisher events,
        DtoMapper mapper, AccessResolver resolver) {
        this.resolver = resolver;
        this.users = users;
        this.hasher = hasher;
        this.tokens = tokens;
        this.clock = clock;
        this.events = events;
        this.mapper = mapper;
        dummyHash = hasher.hash("dummy-password-for-timing");
    }

    LoginResult login(string username, string password) {
        import std.string : strip;
        import std.uni : toLower;
        const now = clock.now;
        auto u = users.byUsername(username.strip.toLower);
        if (u is null || u.passwordHash.length == 0) {
            hasher.verify(password, dummyHash);
            events.publish(DomainEvent("auth.failed", "", "", username, now));
            throw new UnauthorizedException("Invalid user name or password");
        }
        if (u.isLocked(now))
            throw new LockedException("Account temporarily locked after too many failed attempts");
        if (!hasher.verify(password, u.passwordHash)) {
            u.loginFailed(now);
            users.save(u);
            events.publish(DomainEvent("auth.failed", u.id, "", username, now));
            throw new UnauthorizedException("Invalid user name or password");
        }
        if (!u.active)
            throw new UnauthorizedException("User is deactivated");
        u.loginSucceeded(now);
        users.save(u);
        events.publish(DomainEvent("auth.login", u.id, u.id, "", now));
        auto ttl = tokens.ttlSeconds;
        auto token = tokens.issue(TokenClaims(u.id, u.username, roleName(u.role), now.toUnixTime + ttl));
        auto access = resolver.resolve(Principal(u.id, u.username, u.displayName, u.role));
        return LoginResult(token, ttl, mapper.me(u, access, now));
    }

    UserDto me(in Principal p) {
        return mapper.me(require(p), resolver.resolve(p), clock.now);
    }

    void changePassword(in Principal p, string oldPassword, string newPassword) {
        auto u = require(p);
        if (u.passwordHash.length == 0)
            throw new ValidationException("Externally managed users cannot change the password here");
        if (!hasher.verify(oldPassword, u.passwordHash))
            throw new ValidationException("Current password is wrong");
        if (oldPassword == newPassword)
            throw new ValidationException("The new password must differ from the current one");
        checkPasswordPolicy(newPassword);
        u.passwordHash = hasher.hash(newPassword);
        u.mustChangePassword = false;
        u.updatedAt = clock.now;
        u.version_++;
        users.save(u);
        events.publish(DomainEvent("user.password", u.id, u.id, "", clock.now));
    }

    UserDto updateProfile(in Principal p, ProfileInput input) {
        auto u = require(p);
        if (!input.displayName.isNull)
            u.displayName = input.displayName.get;
        if (!input.email.isNull)
            u.email = validEmail(input.email.get);
        u.updatedAt = clock.now;
        u.version_++;
        users.save(u);
        return mapper.me(u, resolver.resolve(p), clock.now);
    }

    private User require(in Principal p) {
        auto u = users.byId(p.userId);
        if (u is null)
            throw new UnauthorizedException("User no longer exists");
        return u;
    }
}
