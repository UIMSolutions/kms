/// Assignment of a user to an area with a role. A user can be a member of many areas with
/// different roles; memberships are not inherited by sub-areas (each area has its own users).
/// The category manager is stored on the area itself (`Space.managerId`).
module uim.myfiori.domain.entities.membership;

import std.datetime.systime : SysTime;
import uim.myfiori.domain.enumerations.spacerole;
import uim.myfiori.domain.exceptions;

final class Membership {
    string id;
    string spaceId;
    string userId;
    SpaceRole role = SpaceRole.reader;
    string createdBy;
    SysTime createdAt;
    SysTime updatedAt;
}

/// Members are readers or editors; "manager" is assigned via the category manager.
SpaceRole validMemberRole(string s) {
    SpaceRole r;
    if (!tryParseSpaceRole(s, r) || r == SpaceRole.manager)
        throw new ValidationException("Member role must be 'reader' or 'editor' "
                ~ "(the category manager is assigned separately)");
    return r;
}
