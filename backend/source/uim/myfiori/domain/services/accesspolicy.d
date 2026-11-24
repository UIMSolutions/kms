/// Authorization rules of the knowledge base.
///
/// | action                         | reader | editor | admin |
/// |--------------------------------|--------|--------|-------|
/// | read / search published items  |   x    |   x    |   x   |
/// | read drafts & archived         |        |   x    |   x   |
/// | create / edit articles, upload |        |   x    |   x   |
/// | delete own items               |        |   x    |   x   |
/// | delete foreign items           |        |        |   x   |
/// | manage users and spaces        |        |        |   x   |
module uim.myfiori.domain.services.accesspolicy;

import uim.myfiori.domain.entities;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types.principal;

struct AccessPolicy {
static:
    bool canReadArticle(in Principal p, in Article a) {
        return a.status == ArticleStatus.published || p.can(Role.editor);
    }

    bool canReadStatus(in Principal p, string status) {
        return status == "published" || status.length == 0 || p.can(Role.editor);
    }

    bool canWrite(in Principal p) {
        return p.can(Role.editor);
    }

    bool canDelete(in Principal p, string ownerId) {
        return p.isAdmin || (p.can(Role.editor) && p.userId == ownerId);
    }

    bool canAdminister(in Principal p) {
        return p.isAdmin;
    }

    void requireWrite(in Principal p) {
        if (!canWrite(p))
            throw new ForbiddenException("Editor role required");
    }

    void requireAdmin(in Principal p) {
        if (!canAdminister(p))
            throw new ForbiddenException("Administrator role required");
    }

    void requireDelete(in Principal p, string ownerId) {
        if (!canDelete(p, ownerId))
            throw new ForbiddenException("Only the owner or an administrator may delete this item");
    }
}

unittest {
    auto reader = Principal("u1", "r", "R", Role.reader);
    auto editor = Principal("u2", "e", "E", Role.editor);
    auto a = new Article;
    assert(!AccessPolicy.canReadArticle(reader, a));
    assert(AccessPolicy.canReadArticle(editor, a));
    a.status = ArticleStatus.published;
    assert(AccessPolicy.canReadArticle(reader, a));
    assert(AccessPolicy.canDelete(editor, "u2") && !AccessPolicy.canDelete(editor, "u9"));
}
