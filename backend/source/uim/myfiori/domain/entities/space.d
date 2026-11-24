/// An area (space) groups articles and documents, e.g. a team, product or topic.
/// Areas form a tree: an area with a `parentId` is a sub-area. Every area has exactly one
/// category manager; its users are assigned through memberships.
module uim.myfiori.domain.entities.space;

import std.datetime.systime : SysTime;

enum maxSpaceDepth = 5; /// area + 4 levels of sub-areas

final class Space {
    string id;
    string parentId;      /// "" = top-level area
    string key;           /// short unique key, e.g. "HR"
    string name;
    string description;
    string icon = "sap-icon://course-book";
    string managerId;     /// category manager (user id)
    string createdBy;
    SysTime createdAt;
    SysTime updatedAt;
    long version_ = 1;

    bool isTopLevel() const {
        return parentId.length == 0;
    }
}
