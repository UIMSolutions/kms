/// User roles. Ordered by privilege: a higher role includes all rights of the lower ones.
module uim.myfiori.domain.enumerations.role;

import std.conv : to;
import std.uni : toLower;

enum Role {
    reader, /// read & search published knowledge, download media
    editor, /// create / edit articles, upload & manage media
    admin   /// manage users and spaces, see everything
}

string roleName(Role r) pure @safe {
    final switch (r) {
    case Role.reader:
        return "reader";
    case Role.editor:
        return "editor";
    case Role.admin:
        return "admin";
    }
}

/// Parses a role name (case-insensitive); returns false for unknown names.
bool tryParseRole(string s, out Role r) @safe {
    switch (s.toLower) {
    case "reader":
        r = Role.reader;
        return true;
    case "editor":
        r = Role.editor;
        return true;
    case "admin":
        r = Role.admin;
        return true;
    default:
        return false;
    }
}

bool atLeast(Role have, Role required) pure @safe nothrow {
    return cast(int) have >= cast(int) required;
}

unittest {
    Role r;
    assert(tryParseRole("Editor", r) && r == Role.editor);
    assert(!tryParseRole("root", r));
    assert(Role.admin.atLeast(Role.editor));
    assert(!Role.reader.atLeast(Role.editor));
    assert(roleName(Role.admin) == "admin");
}
