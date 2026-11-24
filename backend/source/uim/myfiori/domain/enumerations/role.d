/// Global user roles. Content rights are granted per area (see SpaceRole / SpaceAccess);
/// the global role only distinguishes ordinary users from system administrators.
module uim.myfiori.domain.enumerations.role;

import std.uni : toLower;

enum Role {
    user, /// rights come from area memberships and category-manager assignments
    admin /// system administrator: users, all areas, search index, audit
}

string roleName(Role r) pure @safe {
    final switch (r) {
    case Role.user:
        return "user";
    case Role.admin:
        return "admin";
    }
}

/// Parses a role name (case-insensitive). The pre-area names "reader" and "editor"
/// are accepted as `user` (see `isLegacyRole`).
bool tryParseRole(string s, out Role r) @safe {
    switch (s.toLower) {
    case "user", "reader", "editor":
        r = Role.user;
        return true;
    case "admin":
        r = Role.admin;
        return true;
    default:
        return false;
    }
}

/// Global roles of release 1.0 that became area memberships.
bool isLegacyRole(string s) @safe {
    auto l = s.toLower;
    return l == "reader" || l == "editor";
}

bool atLeast(Role have, Role required) pure @safe nothrow {
    return cast(int) have >= cast(int) required;
}

unittest {
    Role r;
    assert(tryParseRole("Admin", r) && r == Role.admin);
    assert(tryParseRole("editor", r) && r == Role.user && isLegacyRole("editor"));
    assert(!tryParseRole("root", r));
    assert(Role.admin.atLeast(Role.user) && !Role.user.atLeast(Role.admin));
}
