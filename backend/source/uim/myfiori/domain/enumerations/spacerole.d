/// Role of a user within one area (space). Ordered by privilege.
module uim.myfiori.domain.enumerations.spacerole;

import std.uni : toLower;

enum SpaceRole {
    none,    /// no access
    reader,  /// read published articles and documents of the area
    editor,  /// additionally create / edit content, see drafts
    manager  /// category manager: everything in the area and its sub-areas incl. members
}

string spaceRoleName(SpaceRole r) pure @safe {
    final switch (r) {
    case SpaceRole.none:
        return "none";
    case SpaceRole.reader:
        return "reader";
    case SpaceRole.editor:
        return "editor";
    case SpaceRole.manager:
        return "manager";
    }
}

bool tryParseSpaceRole(string s, out SpaceRole r) @safe {
    switch (s.toLower) {
    case "reader":
        r = SpaceRole.reader;
        return true;
    case "editor":
        r = SpaceRole.editor;
        return true;
    case "manager":
        r = SpaceRole.manager;
        return true;
    default:
        return false;
    }
}
