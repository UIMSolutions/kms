/// Documents and other media: upload, metadata, file replacement, download, delete.
module uim.myfiori.application.usecases.documentusecases;

import std.algorithm : any, canFind, filter, sort;
import std.array : array;
import std.conv : to;
import std.path : baseName, extension;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

struct MediaSettings {
    ulong maxUploadBytes = 100 * 1024 * 1024;
    ulong quotaBytes = 0; /// 0 = unlimited
    string[] allowedExtensions; /// empty = all except blocked
    string[] blockedExtensions = [".exe", ".bat", ".cmd", ".com", ".msi", ".sh", ".ps1", ".scr", ".dll", ".jar", ".vbs"];
}

final class DocumentInteractor : DocumentUseCase {
    private DocumentRepository documents;
    private ArticleRepository articles;
    private SpaceRepository spaces;
    private BlobStorage blobs;
    private MimeTypes mime;
    private SearchIndexer indexer;
    private AccessResolver resolver;
    private Clock clock;
    private IdGenerator ids;
    private EventPublisher events;
    private DtoMapper mapper;
    private MediaSettings settings;

    this(DocumentRepository documents, ArticleRepository articles, SpaceRepository spaces, BlobStorage blobs,
        MimeTypes mime, SearchIndexer indexer, AccessResolver resolver, Clock clock, IdGenerator ids,
        EventPublisher events, DtoMapper mapper, MediaSettings settings) {
        this.resolver = resolver;
        this.documents = documents;
        this.articles = articles;
        this.spaces = spaces;
        this.blobs = blobs;
        this.mime = mime;
        this.indexer = indexer;
        this.clock = clock;
        this.ids = ids;
        this.events = events;
        this.mapper = mapper;
        this.settings = settings;
    }

    Page!DocumentDto list(in Principal p, DocumentFilter f) {
        auto access = resolver.resolve(p);
        auto text = f.text.strip.toLower;
        auto tag = f.tag.strip.toLower;
        string[] areas;
        if (f.spaceId.length)
            areas = [f.spaceId] ~ (f.includeSubAreas ? access.tree.descendants(f.spaceId) : null);
        auto all = documents.all().filter!((d) {
            if (areas.length && !areas.canFind(d.spaceId))
                return false;
            if (!access.canRead(d.spaceId))
                return false;
            if (f.kind.length && kindName(d.kind) != f.kind)
                return false;
            if (tag.length && !d.tags.canFind(tag))
                return false;
            if (text.length && !d.title.toLower.canFind(text) && !d.fileName.toLower.canFind(text)
                && !d.description.toLower.canFind(text))
                return false;
            return true;
        }).array;
        switch (f.orderBy) {
        case "title":
            all.sort!((a, b) => a.title.toLower < b.title.toLower);
            break;
        case "size desc":
            all.sort!((a, b) => a.size > b.size);
            break;
        case "downloads desc":
            all.sort!((a, b) => a.downloads > b.downloads);
            break;
        default:
            all.sort!((a, b) => a.updatedAt > b.updatedAt);
        }
        Page!DocumentDto r;
        r.total = all.length;
        foreach (d; slicePage(all, f.skip, f.top))
            r.items ~= mapper.document(d, access);
        return r;
    }

    DocumentDto get(in Principal p, string id) {
        auto access = resolver.resolve(p);
        return mapper.document(readable(access, id), access);
    }

    DocumentDto upload(in Principal p, UploadInput input, const(ubyte)[] data) {
        auto access = resolver.resolve(p);
        if (input.spaceId.length == 0)
            throw new ValidationException("Area is required");
        if (spaces.byId(input.spaceId) is null)
            throw new ValidationException("Unknown area");
        access.requireWrite(input.spaceId);
        auto fileName = checkFile(input.fileName, data);
        const now = clock.now;
        auto d = new Document;
        d.id = ids.newId;
        d.spaceId = input.spaceId;
        d.fileName = fileName;
        d.title = input.title.strip.length ? input.title.strip : fileName;
        if (d.title.length > maxTitleLength)
            throw new ValidationException("Title too long (max 200 characters)");
        d.description = input.description;
        d.tags = normalizeTags(input.tags);
        d.mimeType = effectiveMime(input.mimeType, fileName);
        d.kind = classify(d.mimeType, fileName);
        d.blobKey = d.id;
        auto info = blobs.put(d.blobKey, data);
        d.size = info.size;
        d.sha256 = info.sha256;
        d.uploadedBy = d.updatedBy = p.userId;
        d.createdAt = d.updatedAt = now;
        documents.save(d);
        indexer.index(d);
        events.publish(DomainEvent("document.uploaded", d.id, p.userId, d.fileName, now));
        return mapper.document(d, access);
    }

    DocumentDto replaceFile(in Principal p, string id, string fileName, string mimeType, const(ubyte)[] data) {
        auto access = resolver.resolve(p);
        auto d = readable(access, id);
        access.requireWrite(d.spaceId);
        auto name = checkFile(fileName.length ? fileName : d.fileName, data, d.size);
        auto info = blobs.put(d.blobKey, data);
        if (d.title == d.fileName)
            d.title = name;
        d.fileName = name;
        d.mimeType = effectiveMime(mimeType, name);
        d.kind = classify(d.mimeType, name);
        d.size = info.size;
        d.sha256 = info.sha256;
        d.text = "";
        d.textExtracted = false;
        d.fileRevision++;
        d.version_++;
        d.updatedBy = p.userId;
        d.updatedAt = clock.now;
        documents.save(d);
        indexer.index(d);
        events.publish(DomainEvent("document.uploaded", d.id, p.userId, d.fileName, clock.now));
        return mapper.document(d, access);
    }

    DocumentDto update(in Principal p, string id, DocumentInput input) {
        auto access = resolver.resolve(p);
        auto d = readable(access, id);
        access.requireWrite(d.spaceId);
        if (!input.title.isNull) {
            auto t = input.title.get.strip;
            if (t.length == 0 || t.length > maxTitleLength)
                throw new ValidationException("Title must have 1 to 200 characters");
            d.title = t;
        }
        if (!input.description.isNull)
            d.description = input.description.get;
        if (!input.spaceId.isNull && input.spaceId.get != d.spaceId) {
            if (spaces.byId(input.spaceId.get) is null)
                throw new ValidationException("Unknown area");
            access.requireWrite(input.spaceId.get);
            d.spaceId = input.spaceId.get;
        }
        if (!input.tags.isNull)
            d.tags = normalizeTags(input.tags.get);
        d.version_++;
        d.updatedBy = p.userId;
        d.updatedAt = clock.now;
        documents.save(d);
        indexer.index(d);
        return mapper.document(d, access);
    }

    FileContent content(in Principal p, string id) {
        auto d = readable(resolver.resolve(p), id);
        if (!blobs.exists(d.blobKey))
            throw new NotFoundException("File content missing");
        d.downloads++;
        documents.save(d);
        FileContent c;
        c.fileName = d.fileName;
        c.mimeType = d.mimeType;
        c.size = d.size;
        c.etag = `"` ~ d.sha256 ~ `"`;
        c.localPath = blobs.localPath(d.blobKey);
        if (c.localPath.length == 0)
            c.data = blobs.get(d.blobKey);
        return c;
    }

    void remove(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto d = readable(access, id);
        access.requireDelete(d.spaceId, d.uploadedBy);
        // detach from articles
        foreach (a; articles.all())
            if (a.attachmentIds.canFind(d.id)) {
                a.detach(d.id);
                articles.save(a);
            }
        blobs.remove(d.blobKey);
        documents.remove(d.id);
        indexer.remove(d.id);
        events.publish(DomainEvent("document.deleted", d.id, p.userId, d.fileName, clock.now));
    }

    // ------------------------------------------------------------------ helpers

    private Document require(string id) {
        auto d = documents.byId(id);
        if (d is null)
            throw new NotFoundException("Document not found");
        return d;
    }

    private Document readable(in SpaceAccess access, string id) {
        auto d = require(id);
        if (!access.canRead(d.spaceId))
            throw new NotFoundException("Document not found");
        return d;
    }

    private string effectiveMime(string given, string fileName) {
        auto m = given.strip.toLower;
        if (m.length == 0 || m == "application/octet-stream")
            m = mime.ofFile(fileName);
        return m;
    }

    /// Validates name, extension, size and quota; returns the sanitized file name.
    private string checkFile(string rawName, const(ubyte)[] data, ulong replacedSize = 0) {
        auto name = sanitizeFileName(rawName);
        if (name.length == 0)
            throw new ValidationException("File name is required");
        if (data.length == 0)
            throw new ValidationException("The file is empty");
        if (data.length > settings.maxUploadBytes)
            throw new PayloadTooLargeException("File too large (max " ~ (settings.maxUploadBytes / (1024 * 1024))
                    .to!string ~ " MB)");
        auto ext = name.extension.toLower;
        if (settings.blockedExtensions.canFind(ext))
            throw new ValidationException("File type " ~ ext ~ " is not allowed");
        if (settings.allowedExtensions.length && !settings.allowedExtensions.canFind(ext))
            throw new ValidationException("File type " ~ (ext.length ? ext : "(none)") ~ " is not allowed");
        if (settings.quotaBytes && blobs.usedBytes() - replacedSize + data.length > settings.quotaBytes)
            throw new PayloadTooLargeException("Storage quota exceeded");
        return name;
    }
}

/// Strips paths and control / reserved characters from an uploaded file name.
string sanitizeFileName(string raw) {
    import std.array : appender;
    auto n = raw.strip;
    // drop any client path (both separators)
    foreach_reverse (i, c; n)
        if (c == '/' || c == '\\') {
            n = n[i + 1 .. $];
            break;
        }
    auto o = appender!string;
    foreach (char c; n) {
        if (c < 0x20 || c == 0x7f || `<>:"|?*`.canFind(c))
            o ~= '_';
        else
            o ~= c;
    }
    auto r = o[].strip;
    while (r.length && r[0] == '.')
        r = r[1 .. $];
    return r.length > 200 ? r[$ - 200 .. $] : r;
}

unittest {
    assert(sanitizeFileName(`C:\tmp\report<1>.pdf`) == "report_1_.pdf");
    assert(sanitizeFileName("../../etc/passwd") == "passwd");
    assert(sanitizeFileName("..hidden") == "hidden");
}
