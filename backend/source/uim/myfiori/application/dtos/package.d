/// Data transfer objects: request / response models of the use cases.
/// Serialized as JSON by the presentation layer (camelCase field names).
module uim.myfiori.application.dtos;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

// ------------------------------------------------------------------ users & auth

struct UserDto {
    string id;
    string username;
    string displayName;
    string email;
    string role;
    bool active;
    bool external;
    bool locked;
    bool mustChangePassword;
    string lastLoginAt;
    string createdAt;
    string updatedAt;
    long version_;
}

struct LoginResult {
    string token;
    long expiresIn;
    UserDto user;
}

struct ProfileInput {
    Nullable!string displayName;
    Nullable!string email;
}

struct UserInput {
    Nullable!string username;
    Nullable!string displayName;
    Nullable!string email;
    Nullable!string role;
    Nullable!bool active;
    Nullable!string password;
    Nullable!bool mustChangePassword;
}

// ------------------------------------------------------------------ spaces

struct SpaceDto {
    string id;
    string key;
    string name;
    string description;
    string icon;
    size_t articleCount;
    size_t documentCount;
    string createdAt;
    string updatedAt;
    long version_;
}

struct SpaceInput {
    Nullable!string key;
    Nullable!string name;
    Nullable!string description;
    Nullable!string icon;
}

// ------------------------------------------------------------------ articles

struct AttachmentDto {
    string id;
    string title;
    string fileName;
    string mimeType;
    string kind;
    ulong size;
}

struct ArticleDto {
    string id;
    string spaceId;
    string spaceName;
    string title;
    string summary;
    string body;
    string[] tags;
    AttachmentDto[] attachments;
    string status;
    string authorId;
    string authorName;
    string updatedBy;
    string updatedByName;
    string createdAt;
    string updatedAt;
    string publishedAt;
    long version_;
    ulong views;
    bool canEdit;
    bool canDelete;
}

struct ArticleFilter {
    string spaceId;
    string status;
    string tag;
    string authorId;
    string text;
    string orderBy; /// "updatedAt desc" (default), "title", "views desc", "createdAt desc"
    size_t skip;
    size_t top = 50;
    bool withBody;
}

struct ArticleInput {
    Nullable!string spaceId;
    Nullable!string title;
    Nullable!string summary;
    Nullable!string body;
    Nullable!(string[]) tags;
    Nullable!(string[]) attachmentIds;
}

struct ArticleVersionDto {
    string id;
    long version_;
    string title;
    string summary;
    string body;
    string[] tags;
    string status;
    string changedBy;
    string changedByName;
    string changedAt;
}

// ------------------------------------------------------------------ documents / media

struct DocumentDto {
    string id;
    string spaceId;
    string spaceName;
    string title;
    string description;
    string fileName;
    string mimeType;
    string kind;
    ulong size;
    string sha256;
    string[] tags;
    bool textExtracted;
    size_t textLength;
    string uploadedBy;
    string uploadedByName;
    string createdAt;
    string updatedAt;
    long version_;
    uint fileRevision;
    ulong downloads;
    string contentUrl;
    bool canEdit;
    bool canDelete;
}

struct DocumentFilter {
    string spaceId;
    string kind;
    string tag;
    string text;
    string orderBy; /// "updatedAt desc" (default), "title", "size desc", "downloads desc"
    size_t skip;
    size_t top = 50;
}

struct UploadInput {
    string fileName;
    string mimeType;
    string title;
    string description;
    string spaceId;
    string[] tags;
}

struct DocumentInput {
    Nullable!string title;
    Nullable!string description;
    Nullable!string spaceId;
    Nullable!(string[]) tags;
}

/// Binary content for downloads: either a file path (streamed) or in-memory data.
struct FileContent {
    string fileName;
    string mimeType;
    ulong size;
    string etag;
    string localPath;
    ubyte[] data;
}

// ------------------------------------------------------------------ search & statistics

struct SearchHitDto {
    string id;
    string kind;
    string title;
    string snippet;
    double score;
    string spaceId;
    string spaceName;
    string[] tags;
    string status;
    string mediaKind;
    string updatedAt;
}

struct FacetDto {
    string value;
    string label;
    size_t count;
}

struct SearchResultDto {
    string query;
    size_t total;
    SearchHitDto[] hits;
    FacetDto[] kinds;
    FacetDto[] spaces;
    FacetDto[] tags;
    FacetDto[] mediaKinds;
    string[] suggestions;
    double tookMs;
}

struct CountDto {
    string key;
    string label;
    size_t count;
}

struct RecentItemDto {
    string id;
    string kind;
    string title;
    string updatedAt;
    string by;
}

struct StatsDto {
    size_t users;
    size_t spaces;
    size_t articles;
    size_t publishedArticles;
    size_t draftArticles;
    size_t documents;
    ulong storageBytes;
    size_t indexedItems;
    size_t vocabulary;
    CountDto[] mediaKinds;
    CountDto[] topTags;
    RecentItemDto[] recent;
}
