/// A knowledge article (Markdown body) with lifecycle and attachments.
module uim.myfiori.domain.entities.article;

import std.algorithm.searching : canFind;
import std.datetime.systime : SysTime;
import uim.myfiori.domain.enumerations.articlestatus;
import uim.myfiori.domain.exceptions;

enum maxTitleLength = 200;
enum maxBodyLength = 1024 * 1024;

final class Article {
    string id;
    string spaceId;
    string title;
    string summary;
    string body;          /// Markdown
    string[] tags;
    string[] attachmentIds; /// documents linked to this article
    ArticleStatus status = ArticleStatus.draft;
    string authorId;
    string updatedBy;
    SysTime createdAt;
    SysTime updatedAt;
    SysTime publishedAt;
    long version_ = 1;
    ulong views;

    void publish(SysTime now) {
        if (status == ArticleStatus.published)
            throw new ConflictException("Article is already published");
        status = ArticleStatus.published;
        publishedAt = now;
    }

    void archive() {
        if (status == ArticleStatus.archived)
            throw new ConflictException("Article is already archived");
        status = ArticleStatus.archived;
    }

    void reopen() {
        status = ArticleStatus.draft;
    }

    void attach(string documentId) {
        if (!attachmentIds.canFind(documentId))
            attachmentIds ~= documentId;
    }

    void detach(string documentId) {
        import std.algorithm.iteration : filter;
        import std.array : array;
        attachmentIds = attachmentIds.filter!(a => a != documentId).array;
    }
}

/// Validates title / body limits.
void validateArticleText(string title, string body) {
    import std.string : strip;
    if (title.strip.length == 0)
        throw new ValidationException("Title is required");
    if (title.length > maxTitleLength)
        throw new ValidationException("Title too long (max 200 characters)");
    if (body.length > maxBodyLength)
        throw new ValidationException("Article body too large (max 1 MB)");
}

unittest {
    import std.datetime.systime : Clock;
    auto a = new Article;
    a.publish(Clock.currTime);
    assert(a.status == ArticleStatus.published);
    a.attach("d1");
    a.attach("d1");
    assert(a.attachmentIds == ["d1"]);
    a.detach("d1");
    assert(a.attachmentIds.length == 0);
}
