/// Resolves bearer tokens to principals.
///  - local mode: HS256 tokens issued by /api/v1/auth/login
///  - xsuaa mode: RS256 tokens forwarded by the approuter; users are provisioned on first
///    access; the XSUAA scope decides between administrator and user, area roles are
///    assigned inside the KMS by category managers
module uim.myfiori.application.services.identityservice;

import std.algorithm.searching : canFind;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class TokenIdentityService : IdentityService {
    private TokenIssuer tokens;
    private ExternalTokenValidator external; // null in local mode
    private UserRepository users;
    private Clock clock;
    private IdGenerator ids;

    this(TokenIssuer tokens, ExternalTokenValidator external, UserRepository users, Clock clock, IdGenerator ids) {
        this.tokens = tokens;
        this.external = external;
        this.users = users;
        this.clock = clock;
        this.ids = ids;
    }

    Principal authenticate(string bearer) {
        if (bearer.length == 0)
            throw new UnauthorizedException("Missing bearer token");
        auto claims = tokens.verify(bearer);
        if (!claims.isNull) {
            auto u = users.byId(claims.get.userId);
            if (u is null || !u.active)
                throw new UnauthorizedException("User is unknown or inactive");
            return principalOf(u);
        }
        if (external !is null) {
            auto id = external.validate(bearer);
            if (!id.isNull)
                return provision(id.get);
        }
        throw new UnauthorizedException("Invalid or expired token");
    }

    static Principal principalOf(User u) {
        return Principal(u.id, u.username, u.displayName.length ? u.displayName : u.username, u.role);
    }

    private Principal provision(ExternalIdentity x) {
        Role role;
        // area rights come from memberships in the KMS; XSUAA only decides user vs. admin
        if (x.scopes.canFind("Admin"))
            role = Role.admin;
        else if (x.scopes.canFind("User") || x.scopes.canFind("Editor") || x.scopes.canFind("Reader"))
            role = Role.user;
        else
            throw new ForbiddenException("No KMS role assigned");
        auto u = users.byExternalId(x.userName);
        const now = clock.now;
        if (u is null) {
            u = new User;
            u.id = ids.newId;
            u.externalId = x.userName;
            u.username = uniqueName(x.userName);
            u.createdAt = now;
        }
        if (!u.active)
            throw new UnauthorizedException("User is deactivated");
        auto name = (x.givenName ~ " " ~ x.familyName);
        import std.string : strip;
        if (name.strip.length)
            u.displayName = name.strip;
        if (x.email.length)
            u.email = x.email;
        if (u.role != role || u.lastLoginAt == u.lastLoginAt.init) {
            u.role = role;
            u.lastLoginAt = now;
            u.updatedAt = now;
            users.save(u);
        }
        return principalOf(u);
    }

    private string uniqueName(string ext) {
        import std.algorithm : filter, map;
        import std.array : array;
        import std.ascii : isAlphaNum;
        import std.conv : to;
        import std.uni : toLower;
        auto base = ext.toLower.filter!(c => c < 0x80 && (isAlphaNum(cast(char) c) || c == '.' || c == '_' || c == '-'))
            .map!(c => cast(char) c).array.idup;
        if (base.length < 3)
            base = "user";
        auto name = base;
        for (int i = 2; users.byUsername(name) !is null; i++)
            name = base ~ i.to!string;
        return name;
    }
}
