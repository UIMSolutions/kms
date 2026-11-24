/// /api/v1/documents: upload, metadata, file replacement, streaming download (with Range).
///
/// Uploads accept either
///  - a raw body (Content-Type = file type) with headers X-File-Name, X-Title, X-Space,
///    X-Tags (comma separated), X-Description - all values URL-encoded, or
///  - multipart/form-data with a `file` part and form fields title, spaceId, tags, description.
module uim.myfiori.presentation.http.documentcontroller;

import std.algorithm.searching : canFind, startsWith;
import std.file : read;
import std.string : strip;
import vibe.core.path : NativePath;
import vibe.data.json;
import vibe.http.fileserver : sendFile;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.stream.operations : readAll;
import vibe.textfilter.urlencode : urlDecode, urlEncode;
import uim.myfiori.application.dtos;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types.tags : parseTagList;
import uim.myfiori.infrastructure.monitoring : RequestMetrics;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class DocumentController {
    private DocumentUseCase documents;
    private IdentityService identity;
    private size_t maxBody;
    private size_t maxUpload;
    private RequestMetrics metrics;

    this(DocumentUseCase documents, IdentityService identity, size_t maxBody, size_t maxUpload, RequestMetrics metrics) {
        this.documents = documents;
        this.identity = identity;
        this.maxBody = maxBody;
        this.maxUpload = maxUpload;
        this.metrics = metrics;
    }

    private static string hdr(HTTPServerRequest req, string name) {
        auto v = req.headers.get(name, "");
        try
            return urlDecode(v).strip;
        catch (Exception)
            return v.strip;
    }

    private struct Upload {
        UploadInput input;
        ubyte[] data;
    }

    private Upload readUpload(HTTPServerRequest req) {
        Upload u;
        auto ct = req.headers.get("Content-Type", "");
        if (ct.startsWith("multipart/form-data")) {
            auto fp = "file" in req.files;
            if (fp is null)
                throw new ValidationException("multipart field 'file' missing");
            u.data = cast(ubyte[]) read(fp.tempPath.toString);
            u.input.fileName = fp.filename.name;
            u.input.mimeType = fp.headers.get("Content-Type", "");
            u.input.title = req.form.get("title", "");
            u.input.spaceId = req.form.get("spaceId", "");
            u.input.description = req.form.get("description", "");
            u.input.tags = parseTagList(req.form.get("tags", ""));
        } else {
            u.data = req.bodyReader.readAll(maxUpload + 1);
            u.input.fileName = hdr(req, "X-File-Name");
            u.input.mimeType = ct;
            u.input.title = hdr(req, "X-Title");
            u.input.spaceId = hdr(req, "X-Space");
            u.input.description = hdr(req, "X-Description");
            u.input.tags = parseTagList(hdr(req, "X-Tags"));
        }
        if (u.data.length > maxUpload)
            throw new PayloadTooLargeException("File too large");
        if (metrics !is null)
            metrics.recordUpload(u.data.length);
        return u;
    }

    static DocumentInput parseInput(Json b) {
        DocumentInput i;
        i.title = optString(b, "title");
        i.description = optString(b, "description");
        i.spaceId = optString(b, "spaceId");
        i.tags = optStrings(b, "tags");
        return i;
    }

    /// Types a browser may render inline without script execution risk.
    static bool inlineSafe(string mime) {
        return mime.startsWith("video/") || mime.startsWith("audio/") || [
            "image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp", "application/pdf",
            "text/plain", "text/csv", "text/markdown"
        ].canFind(mime);
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/documents", authed(identity, (p, req, res) {
                DocumentFilter f;
                f.spaceId = qs(req, "space");
                f.includeSubAreas = qs(req, "deep") == "true";
                f.kind = qs(req, "kind");
                f.tag = qs(req, "tag");
                f.text = qs(req, "q");
                f.orderBy = qs(req, "orderBy");
                f.skip = qsNum(req, "skip", 0);
                f.top = qsNum(req, "top", 50, 500);
                sendJson(res, documents.list(p, f));
            }));
        r.post(apiBase ~ "/documents", authed(identity, (p, req, res) {
                auto u = readUpload(req);
                auto d = documents.upload(p, u.input, u.data);
                res.headers["Location"] = apiBase ~ "/documents/" ~ d.id;
                sendJson(res, d, 201);
            }));
        r.get(apiBase ~ "/documents/:id", authed(identity, (p, req, res) {
                sendJson(res, documents.get(p, req.params["id"]));
            }));
        r.patch(apiBase ~ "/documents/:id", authed(identity, (p, req, res) {
                sendJson(res, documents.update(p, req.params["id"], parseInput(readJsonBody(req, maxBody))));
            }));
        r.delete_(apiBase ~ "/documents/:id", authed(identity, (p, req, res) {
                documents.remove(p, req.params["id"]);
                sendNoContent(res);
            }));
        r.put(apiBase ~ "/documents/:id/content", authed(identity, (p, req, res) {
                auto u = readUpload(req);
                sendJson(res, documents.replaceFile(p, req.params["id"], u.input.fileName, u.input.mimeType, u.data));
            }));
        r.get(apiBase ~ "/documents/:id/content", authed(identity, (p, req, res) {
                auto c = documents.content(p, req.params["id"]);
                const inline = qs(req, "download") != "true" && inlineSafe(c.mimeType);
                res.headers["Content-Type"] = c.mimeType.length ? c.mimeType : "application/octet-stream";
                res.headers["Content-Disposition"] = (inline ? "inline" : "attachment")
                    ~ `; filename="` ~ asciiFallback(c.fileName) ~ `"; filename*=UTF-8''` ~ urlEncode(c.fileName);
                res.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; media-src 'self'; "
                    ~ "style-src 'unsafe-inline'; sandbox";
                res.headers["Cache-Control"] = "private, no-cache";
                if (c.localPath.length)
                    sendFile(req, res, NativePath(c.localPath));
                else {
                    res.headers["ETag"] = c.etag;
                    res.writeBody(c.data, c.mimeType);
                }
            }));
    }

    private static string asciiFallback(string name) {
        auto b = new char[name.length];
        size_t n;
        foreach (char c; name)
            b[n++] = (c < 0x20 || c >= 0x7f || c == '"' || c == '\\') ? '_' : c;
        return cast(string) b[0 .. n];
    }
}
