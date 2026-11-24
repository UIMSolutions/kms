/// Technical storage models ("table schemas") as persisted in the JSON files.
/// All fields are optional so that older files stay readable after schema extensions.
module uim.myfiori.persistence.records;

import vibe.data.serialization : optional;

enum Collections : string {
    users = "users",
    spaces = "spaces",
    articles = "articles",
    articleVersions = "article_versions",
    memberships = "memberships",
    documents = "documents"
}

struct UserRecord {
    string id;
    @optional string username;
    @optional string displayName;
    @optional string email;
    @optional string role;
    @optional bool active = true;
    @optional string passwordHash;
    @optional string externalId;
    @optional bool mustChangePassword;
    @optional uint failedLogins;
    @optional string lockedUntil;
    @optional string lastLoginAt;
    @optional string createdAt;
    @optional string updatedAt;
    @optional long version_ = 1;
}

struct SpaceRecord {
    string id;
    @optional string parentId;
    @optional string managerId;
    @optional string key;
    @optional string name;
    @optional string description;
    @optional string icon;
    @optional string createdBy;
    @optional string createdAt;
    @optional string updatedAt;
    @optional long version_ = 1;
}

struct ArticleRecord {
    string id;
    @optional string spaceId;
    @optional string title;
    @optional string summary;
    @optional string body;
    @optional string[] tags;
    @optional string[] attachmentIds;
    @optional string status;
    @optional string authorId;
    @optional string updatedBy;
    @optional string createdAt;
    @optional string updatedAt;
    @optional string publishedAt;
    @optional long version_ = 1;
    @optional ulong views;
}

struct ArticleVersionRecord {
    string id;
    @optional string articleId;
    @optional long version_;
    @optional string title;
    @optional string summary;
    @optional string body;
    @optional string[] tags;
    @optional string status;
    @optional string changedBy;
    @optional string changedAt;
}

struct DocumentRecord {
    string id;
    @optional string spaceId;
    @optional string title;
    @optional string description;
    @optional string fileName;
    @optional string mimeType;
    @optional string kind;
    @optional ulong size;
    @optional string sha256;
    @optional string[] tags;
    @optional string blobKey;
    @optional string text;
    @optional bool textExtracted;
    @optional string uploadedBy;
    @optional string updatedBy;
    @optional string createdAt;
    @optional string updatedAt;
    @optional long version_ = 1;
    @optional uint fileRevision = 1;
    @optional ulong downloads;
}

struct MembershipRecord {
    string id;
    @optional string spaceId;
    @optional string userId;
    @optional string role;
    @optional string createdBy;
    @optional string createdAt;
    @optional string updatedAt;
}
