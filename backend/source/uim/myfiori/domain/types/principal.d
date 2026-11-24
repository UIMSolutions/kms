/// The authenticated caller of a use case.
module uim.myfiori.domain.types.principal;

import uim.myfiori.domain.enumerations.role;

struct Principal {
    string userId;
    string username;
    string displayName;
    Role role;

    bool can(Role required) const pure @safe nothrow {
        return role.atLeast(required);
    }

    bool isAdmin() const pure @safe nothrow {
        return role == Role.admin;
    }
}
