/// Immutable snapshot of an article taken before each change (history / restore).
module uim.myfiori.domain.entities.articleversion;

import std.datetime.systime : SysTime;

final class ArticleVersion {
    string id;
    string articleId;
    long version_;
    string title;
    string summary;
    string body;
    string[] tags;
    string status;
    string changedBy;
    SysTime changedAt;
}
