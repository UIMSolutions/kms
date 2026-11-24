/// Converters between persisted records and domain entities.
module uim.myfiori.persistence.mappers;

import std.datetime.systime : SysTime;
import uim.myfiori.domain;
import uim.myfiori.persistence.records;

string toStored(SysTime t) {
    return t == SysTime.init ? "" : t.toUTC.toISOExtString;
}

SysTime fromStored(string s) {
    if (s.length == 0)
        return SysTime.init;
    try
        return SysTime.fromISOExtString(s);
    catch (Exception)
        return SysTime.init;
}

// ------------------------------------------------------------------ users

UserRecord toRecord(User u) {
    return UserRecord(u.id, u.username, u.displayName, u.email, roleName(u.role), u.active, u.passwordHash,
        u.externalId, u.mustChangePassword, u.failedLogins, toStored(u.lockedUntil), toStored(u.lastLoginAt),
        toStored(u.createdAt), toStored(u.updatedAt), u.version_);
}

User toEntity(in UserRecord r) {
    auto u = new User;
    u.id = r.id;
    u.username = r.username;
    u.displayName = r.displayName;
    u.email = r.email;
    Role role;
    u.role = tryParseRole(r.role, role) ? role : Role.user;
    if (isLegacyRole(r.role))
        u.legacyRole = r.role;
    u.active = r.active;
    u.passwordHash = r.passwordHash;
    u.externalId = r.externalId;
    u.mustChangePassword = r.mustChangePassword;
    u.failedLogins = r.failedLogins;
    u.lockedUntil = fromStored(r.lockedUntil);
    u.lastLoginAt = fromStored(r.lastLoginAt);
    u.createdAt = fromStored(r.createdAt);
    u.updatedAt = fromStored(r.updatedAt);
    u.version_ = r.version_;
    return u;
}

// ------------------------------------------------------------------ spaces

SpaceRecord toRecord(Space s) {
    return SpaceRecord(s.id, s.parentId, s.managerId, s.key, s.name, s.description, s.icon, s.createdBy, toStored(s.createdAt),
        toStored(s.updatedAt), s.version_);
}

Space toEntity(in SpaceRecord r) {
    auto s = new Space;
    s.id = r.id;
    s.parentId = r.parentId;
    s.managerId = r.managerId;
    s.key = r.key;
    s.name = r.name;
    s.description = r.description;
    if (r.icon.length)
        s.icon = r.icon;
    s.createdBy = r.createdBy;
    s.createdAt = fromStored(r.createdAt);
    s.updatedAt = fromStored(r.updatedAt);
    s.version_ = r.version_;
    return s;
}

// ------------------------------------------------------------------ memberships

MembershipRecord toRecord(Membership m) {
    return MembershipRecord(m.id, m.spaceId, m.userId, spaceRoleName(m.role), m.createdBy, toStored(m.createdAt),
        toStored(m.updatedAt));
}

Membership toEntity(in MembershipRecord r) {
    auto m = new Membership;
    m.id = r.id;
    m.spaceId = r.spaceId;
    m.userId = r.userId;
    SpaceRole role;
    m.role = tryParseSpaceRole(r.role, role) && role != SpaceRole.manager ? role : SpaceRole.reader;
    m.createdBy = r.createdBy;
    m.createdAt = fromStored(r.createdAt);
    m.updatedAt = fromStored(r.updatedAt);
    return m;
}

// ------------------------------------------------------------------ articles

ArticleRecord toRecord(Article a) {
    return ArticleRecord(a.id, a.spaceId, a.title, a.summary, a.body, a.tags.dup, a.attachmentIds.dup,
        statusName(a.status), a.authorId, a.updatedBy, toStored(a.createdAt), toStored(a.updatedAt),
        toStored(a.publishedAt), a.version_, a.views);
}

Article toEntity(in ArticleRecord r) {
    auto a = new Article;
    a.id = r.id;
    a.spaceId = r.spaceId;
    a.title = r.title;
    a.summary = r.summary;
    a.body = r.body;
    a.tags = r.tags.dup;
    a.attachmentIds = r.attachmentIds.dup;
    ArticleStatus st;
    a.status = tryParseStatus(r.status, st) ? st : ArticleStatus.draft;
    a.authorId = r.authorId;
    a.updatedBy = r.updatedBy;
    a.createdAt = fromStored(r.createdAt);
    a.updatedAt = fromStored(r.updatedAt);
    a.publishedAt = fromStored(r.publishedAt);
    a.version_ = r.version_;
    a.views = r.views;
    return a;
}

ArticleVersionRecord toRecord(ArticleVersion v) {
    return ArticleVersionRecord(v.id, v.articleId, v.version_, v.title, v.summary, v.body, v.tags.dup, v.status,
        v.changedBy, toStored(v.changedAt));
}

ArticleVersion toEntity(in ArticleVersionRecord r) {
    auto v = new ArticleVersion;
    v.id = r.id;
    v.articleId = r.articleId;
    v.version_ = r.version_;
    v.title = r.title;
    v.summary = r.summary;
    v.body = r.body;
    v.tags = r.tags.dup;
    v.status = r.status;
    v.changedBy = r.changedBy;
    v.changedAt = fromStored(r.changedAt);
    return v;
}

// ------------------------------------------------------------------ documents

DocumentRecord toRecord(Document d) {
    return DocumentRecord(d.id, d.spaceId, d.title, d.description, d.fileName, d.mimeType, kindName(d.kind),
        d.size, d.sha256, d.tags.dup, d.blobKey, d.text, d.textExtracted, d.uploadedBy, d.updatedBy,
        toStored(d.createdAt), toStored(d.updatedAt), d.version_, d.fileRevision, d.downloads);
}

Document toEntity(in DocumentRecord r) {
    auto d = new Document;
    d.id = r.id;
    d.spaceId = r.spaceId;
    d.title = r.title;
    d.description = r.description;
    d.fileName = r.fileName;
    d.mimeType = r.mimeType;
    d.kind = classify(r.mimeType, r.fileName);
    d.size = r.size;
    d.sha256 = r.sha256;
    d.tags = r.tags.dup;
    d.blobKey = r.blobKey.length ? r.blobKey : r.id;
    d.text = r.text;
    d.textExtracted = r.textExtracted;
    d.uploadedBy = r.uploadedBy;
    d.updatedBy = r.updatedBy;
    d.createdAt = fromStored(r.createdAt);
    d.updatedAt = fromStored(r.updatedAt);
    d.version_ = r.version_;
    d.fileRevision = r.fileRevision;
    d.downloads = r.downloads;
    return d;
}
