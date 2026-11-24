/// Lifecycle of a knowledge article.
module uim.myfiori.domain.enumerations.articlestatus;

import std.uni : toLower;

enum ArticleStatus {
    draft,
    published,
    archived
}

string statusName(ArticleStatus s) pure @safe {
    final switch (s) {
    case ArticleStatus.draft:
        return "draft";
    case ArticleStatus.published:
        return "published";
    case ArticleStatus.archived:
        return "archived";
    }
}

bool tryParseStatus(string s, out ArticleStatus r) @safe {
    switch (s.toLower) {
    case "draft":
        r = ArticleStatus.draft;
        return true;
    case "published":
        r = ArticleStatus.published;
        return true;
    case "archived":
        r = ArticleStatus.archived;
        return true;
    default:
        return false;
    }
}
