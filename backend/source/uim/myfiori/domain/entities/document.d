/// An uploaded file (document, image, video, audio, archive ...). The binary lives in the
/// blob storage; this entity holds the metadata and the extracted full text.
module uim.myfiori.domain.entities.document;

import std.datetime.systime : SysTime;
import uim.myfiori.domain.enumerations.mediakind;

final class Document {
    string id;
    string spaceId;
    string title;
    string description;
    string fileName;
    string mimeType;
    MediaKind kind = MediaKind.other;
    ulong size;
    string sha256;
    string[] tags;
    string blobKey;       /// key in the blob storage
    string text;          /// extracted text for the search engine (may be empty)
    bool textExtracted;
    string uploadedBy;
    string updatedBy;
    SysTime createdAt;
    SysTime updatedAt;
    long version_ = 1;    /// incremented on metadata change and file replacement
    uint fileRevision = 1; /// incremented on file replacement only
    ulong downloads;
}
