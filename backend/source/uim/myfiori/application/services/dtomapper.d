/// Entity -> DTO conversion (resolves user and space names).
module uim.myfiori.application.services.dtomapper;

import std.datetime.systime : SysTime;
import uim.myfiori.application.dtos;
import uim.myfiori.domain;
import uim.myfiori.ports.repositories;

string iso(SysTime t) {
    return t == SysTime.init ? "" : t.toUTC.toISOExtString;
}

final class DtoMapper {
    private UserRepository users;
    private SpaceRepository spaces;
    private DocumentRepository documents;

    this(UserRepository users, SpaceRepository spaces, DocumentRepository documents) {
        this.users = users;
        this.spaces = spaces;
        this.documents = documents;
    }

    string userName(string id) {
        if (id.length == 0)
            return "";
        auto u = users.byId(id);
        return u is null ? "(deleted user)" : (u.displayName.length ? u.displayName : u.username);
    }

    string spaceName(string id) {
        if (id.length == 0)
            return "";
        auto s = spaces.byId(id);
        return s is null ? "" : s.name;
    }

    UserDto user(User u, SysTime now) {
        UserDto d;
        d.id = u.id;
        d.username = u.username;
        d.displayName = u.displayName;
        d.email = u.email;
        d.role = roleName(u.role);
        d.active = u.active;
        d.external = u.externalId.length > 0;
        d.locked = u.isLocked(now);
        d.mustChangePassword = u.mustChangePassword;
        d.lastLoginAt = iso(u.lastLoginAt);
        d.createdAt = iso(u.createdAt);
        d.updatedAt = iso(u.updatedAt);
        d.version_ = u.version_;
        return d;
    }

    SpaceDto space(Space s, size_t articleCount, size_t documentCount) {
        SpaceDto d;
        d.id = s.id;
        d.key = s.key;
        d.name = s.name;
        d.description = s.description;
        d.icon = s.icon;
        d.articleCount = articleCount;
        d.documentCount = documentCount;
        d.createdAt = iso(s.createdAt);
        d.updatedAt = iso(s.updatedAt);
        d.version_ = s.version_;
        return d;
    }

    ArticleDto article(Article a, in Principal p, bool withBody = true) {
        ArticleDto d;
        d.id = a.id;
        d.spaceId = a.spaceId;
        d.spaceName = spaceName(a.spaceId);
        d.title = a.title;
        d.summary = a.summary;
        if (withBody) {
            d.body = a.body;
            foreach (id; a.attachmentIds) {
                auto doc = documents.byId(id);
                if (doc !is null)
                    d.attachments ~= AttachmentDto(doc.id, doc.title, doc.fileName, doc.mimeType,
                        kindName(doc.kind), doc.size);
            }
        }
        d.tags = a.tags.dup;
        d.status = statusName(a.status);
        d.authorId = a.authorId;
        d.authorName = userName(a.authorId);
        d.updatedBy = a.updatedBy;
        d.updatedByName = userName(a.updatedBy);
        d.createdAt = iso(a.createdAt);
        d.updatedAt = iso(a.updatedAt);
        d.publishedAt = iso(a.publishedAt);
        d.version_ = a.version_;
        d.views = a.views;
        d.canEdit = AccessPolicy.canWrite(p);
        d.canDelete = AccessPolicy.canDelete(p, a.authorId);
        return d;
    }

    ArticleVersionDto articleVersion(ArticleVersion v) {
        return ArticleVersionDto(v.id, v.version_, v.title, v.summary, v.body, v.tags.dup, v.status,
            v.changedBy, userName(v.changedBy), iso(v.changedAt));
    }

    DocumentDto document(Document doc, in Principal p) {
        DocumentDto d;
        d.id = doc.id;
        d.spaceId = doc.spaceId;
        d.spaceName = spaceName(doc.spaceId);
        d.title = doc.title;
        d.description = doc.description;
        d.fileName = doc.fileName;
        d.mimeType = doc.mimeType;
        d.kind = kindName(doc.kind);
        d.size = doc.size;
        d.sha256 = doc.sha256;
        d.tags = doc.tags.dup;
        d.textExtracted = doc.textExtracted;
        d.textLength = doc.text.length;
        d.uploadedBy = doc.uploadedBy;
        d.uploadedByName = userName(doc.uploadedBy);
        d.createdAt = iso(doc.createdAt);
        d.updatedAt = iso(doc.updatedAt);
        d.version_ = doc.version_;
        d.fileRevision = doc.fileRevision;
        d.downloads = doc.downloads;
        d.contentUrl = "/api/v1/documents/" ~ doc.id ~ "/content";
        d.canEdit = AccessPolicy.canWrite(p);
        d.canDelete = AccessPolicy.canDelete(p, doc.uploadedBy);
        return d;
    }
}
