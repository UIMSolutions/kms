/// Areas (spaces) and sub-areas: hierarchy, category manager, members.
module uim.myfiori.application.usecases.spaceusecases;

import std.algorithm : canFind, filter, sort;
import std.array : array;
import std.range : walkLength;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class SpaceInteractor : SpaceUseCase {
    private SpaceRepository spaces;
    private MembershipRepository memberships;
    private UserRepository users;
    private ArticleRepository articles;
    private DocumentRepository documents;
    private AccessResolver resolver;
    private Clock clock;
    private IdGenerator ids;
    private EventPublisher events;
    private DtoMapper mapper;

    this(SpaceRepository spaces, MembershipRepository memberships, UserRepository users, ArticleRepository articles,
        DocumentRepository documents, AccessResolver resolver, Clock clock, IdGenerator ids, EventPublisher events,
        DtoMapper mapper) {
        this.spaces = spaces;
        this.memberships = memberships;
        this.users = users;
        this.articles = articles;
        this.documents = documents;
        this.resolver = resolver;
        this.clock = clock;
        this.ids = ids;
        this.events = events;
        this.mapper = mapper;
    }

    /// Areas the caller can see, in tree order (parents before children, siblings by name).
    SpaceDto[] list(in Principal p) {
        auto access = resolver.resolve(p);
        auto tree = access.tree;
        SpaceDto[] r;
        void walk(Space[] level) {
            level.sort!((a, b) => a.name.toLower < b.name.toLower);
            foreach (s; level) {
                if (access.canRead(s.id))
                    r ~= toDto(access, s);
                Space[] kids;
                foreach (c; tree.children(s.id))
                    kids ~= tree.get(c);
                walk(kids);
            }
        }

        walk(spaces.all().filter!(s => s.parentId.length == 0 || tree.get(s.parentId) is null).array);
        return r;
    }

    SpaceDto get(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        access.requireRead(s.id);
        return toDto(access, s);
    }

    SpaceDto create(in Principal p, SpaceInput input) {
        auto access = resolver.resolve(p);
        auto parentId = input.parentId.isNull ? "" : input.parentId.get.strip;
        if (!access.canCreateIn(parentId))
            throw new ForbiddenException(parentId.length
                    ? "Only the category manager of the parent area may create sub-areas"
                    : "Only administrators may create top-level areas");
        access.tree.checkParent("", parentId);
        if (input.key.isNull || input.name.isNull || input.name.get.strip.length == 0)
            throw new ValidationException("Key and name are required");
        auto key = validSpaceKey(input.key.get);
        if (spaces.byKey(key) !is null)
            throw new ConflictException("Area key already exists: " ~ key);
        const now = clock.now;
        auto s = new Space;
        s.id = ids.newId;
        s.parentId = parentId;
        s.key = key;
        s.name = input.name.get.strip;
        if (!input.description.isNull)
            s.description = input.description.get;
        if (!input.icon.isNull && input.icon.get.length)
            s.icon = input.icon.get;
        // every area needs a category manager - default: the creator
        s.managerId = requireActiveUser(input.managerId.isNull || input.managerId.get.length == 0
                ? p.userId : input.managerId.get).id;
        s.createdBy = p.userId;
        s.createdAt = s.updatedAt = now;
        spaces.save(s);
        events.publish(DomainEvent("space.created", s.id, p.userId, s.key, now));
        return toDto(resolver.resolve(p), s);
    }

    SpaceDto update(in Principal p, string id, SpaceInput input) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        access.requireManage(s.id);
        if (!input.key.isNull) {
            auto key = validSpaceKey(input.key.get);
            auto other = spaces.byKey(key);
            if (other !is null && other.id != s.id)
                throw new ConflictException("Area key already exists: " ~ key);
            s.key = key;
        }
        if (!input.name.isNull) {
            if (input.name.get.strip.length == 0)
                throw new ValidationException("Name is required");
            s.name = input.name.get.strip;
        }
        if (!input.description.isNull)
            s.description = input.description.get;
        if (!input.icon.isNull && input.icon.get.length)
            s.icon = input.icon.get;
        if (!input.parentId.isNull && input.parentId.get.strip != s.parentId) {
            // moving an area changes who governs it: administrators only
            AccessPolicy.requireAdmin(p);
            auto newParent = input.parentId.get.strip;
            access.tree.checkParent(s.id, newParent);
            s.parentId = newParent;
            events.publish(DomainEvent("space.moved", s.id, p.userId, newParent, clock.now));
        }
        if (!input.managerId.isNull && input.managerId.get != s.managerId)
            assignManager(access, p, s, input.managerId.get);
        s.updatedAt = clock.now;
        s.version_++;
        spaces.save(s);
        return toDto(resolver.resolve(p), s);
    }

    void remove(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        if (!access.canGovern(s))
            throw new ForbiddenException(s.isTopLevel ? "Only administrators may delete top-level areas"
                    : "Only the category manager of the parent area may delete a sub-area");
        if (access.tree.children(s.id).length)
            throw new ConflictException("The area has sub-areas - delete or move them first");
        if (articles.bySpace(s.id).length || documents.bySpace(s.id).length)
            throw new ConflictException("The area is not empty - move or delete its articles and documents first");
        foreach (m; memberships.bySpace(s.id))
            memberships.remove(m.id);
        spaces.remove(s.id);
        events.publish(DomainEvent("space.deleted", s.id, p.userId, s.key, clock.now));
    }

    SpaceDto setManager(in Principal p, string id, string userId) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        assignManager(access, p, s, userId);
        s.updatedAt = clock.now;
        s.version_++;
        spaces.save(s);
        return toDto(resolver.resolve(p), s);
    }

    /// Category manager, managers inherited from parent areas, then members (by name).
    MemberDto[] members(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        access.requireRead(s.id);
        MemberDto[] r;
        if (auto m = users.byId(s.managerId))
            r ~= memberOf(s.id, m, "", "manager", "manager", "");
        foreach (anc; access.tree.ancestors(s.id))
            if (auto m = users.byId(anc.managerId))
                if (!r.canFind!(x => x.userId == m.id))
                    r ~= memberOf(s.id, m, "", "manager", "inherited", access.tree.path(anc.id));
        MemberDto[] plain;
        foreach (ms; memberships.bySpace(s.id))
            if (auto u = users.byId(ms.userId))
                plain ~= memberOf(s.id, u, ms.id, spaceRoleName(ms.role), "member", "");
        plain.sort!((a, b) => a.displayName.toLower < b.displayName.toLower);
        return r ~ plain;
    }

    MemberDto setMember(in Principal p, string id, string userId, string role) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        access.requireManage(s.id);
        auto u = requireActiveUser(userId);
        auto r = validMemberRole(role);
        const now = clock.now;
        auto m = memberships.find(s.id, u.id);
        if (m is null) {
            m = new Membership;
            m.id = ids.newId;
            m.spaceId = s.id;
            m.userId = u.id;
            m.createdBy = p.userId;
            m.createdAt = now;
        }
        m.role = r;
        m.updatedAt = now;
        memberships.save(m);
        events.publish(DomainEvent("space.member", s.id, p.userId, u.username ~ "=" ~ spaceRoleName(r), now));
        return memberOf(s.id, u, m.id, spaceRoleName(r), "member", "");
    }

    void removeMember(in Principal p, string id, string userId) {
        auto access = resolver.resolve(p);
        auto s = require(id);
        access.requireManage(s.id);
        auto m = memberships.find(s.id, userId);
        if (m is null)
            throw new NotFoundException("The user is not a member of this area");
        memberships.remove(m.id);
        events.publish(DomainEvent("space.member-removed", s.id, p.userId, userId, clock.now));
    }

    // ------------------------------------------------------------------ helpers

    private void assignManager(in SpaceAccess access, in Principal p, Space s, string userId) {
        if (!access.canGovern(s))
            throw new ForbiddenException(s.isTopLevel
                    ? "Only administrators may assign the category manager of a top-level area"
                    : "Only the category manager of the parent area may assign the manager of a sub-area");
        auto u = requireActiveUser(userId);
        s.managerId = u.id;
        events.publish(DomainEvent("space.manager", s.id, p.userId, u.username, clock.now));
    }

    private Space require(string id) {
        auto s = spaces.byId(id);
        if (s is null)
            throw new NotFoundException("Area not found");
        return s;
    }

    private User requireActiveUser(string id) {
        auto u = users.byId(id);
        if (u is null || !u.active)
            throw new ValidationException("Unknown or inactive user");
        return u;
    }

    private static MemberDto memberOf(string spaceId, User u, string membershipId, string role, string source,
        string sourcePath) {
        return MemberDto(membershipId, spaceId, u.id, u.username, u.displayName.length ? u.displayName : u.username,
            u.email, role, source, sourcePath, u.active);
    }

    private SpaceDto toDto(in SpaceAccess access, Space s) {
        auto arts = articles.bySpace(s.id).filter!(a => access.canReadArticle(a)).walkLength;
        return mapper.space(s, access, memberships.bySpace(s.id).length, arts, documents.bySpace(s.id).length);
    }
}
