/// A knowledge space groups articles and documents (e.g. a team, product or topic).
module uim.myfiori.domain.entities.space;

import std.datetime.systime : SysTime;

final class Space {
    string id;
    string key;           /// short unique key, e.g. "HR"
    string name;
    string description;
    string icon = "sap-icon://course-book";
    string createdBy;
    SysTime createdAt;
    SysTime updatedAt;
    long version_ = 1;
}
