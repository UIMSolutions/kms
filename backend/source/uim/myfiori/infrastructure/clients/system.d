/// System adapters: wall clock, UUID ids, extension based MIME types.
module uim.myfiori.infrastructure.clients.system;

import std.datetime.systime : SysTime, StdClock = Clock;
import std.path : extension;
import std.uni : toLower;
import std.uuid : randomUUID;
import uim.myfiori.ports.services;

final class SystemClock : Clock {
    SysTime now() {
        return StdClock.currTime;
    }
}

final class UuidGenerator : IdGenerator {
    string newId() {
        return randomUUID.toString;
    }
}

final class ExtensionMimeTypes : MimeTypes {
    private static immutable string[string] table;

    shared static this() {
        table = [
            ".pdf": "application/pdf", ".txt": "text/plain", ".md": "text/markdown", ".csv": "text/csv",
            ".json": "application/json", ".xml": "application/xml", ".html": "text/html", ".htm": "text/html",
            ".log": "text/plain", ".yaml": "application/yaml", ".yml": "application/yaml", ".rtf": "application/rtf",
            ".doc": "application/msword",
            ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            ".xls": "application/vnd.ms-excel",
            ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            ".ppt": "application/vnd.ms-powerpoint",
            ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            ".odt": "application/vnd.oasis.opendocument.text",
            ".ods": "application/vnd.oasis.opendocument.spreadsheet",
            ".odp": "application/vnd.oasis.opendocument.presentation",
            ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
            ".webp": "image/webp", ".svg": "image/svg+xml", ".bmp": "image/bmp", ".tif": "image/tiff",
            ".tiff": "image/tiff", ".ico": "image/x-icon", ".avif": "image/avif",
            ".mp4": "video/mp4", ".webm": "video/webm", ".mov": "video/quicktime", ".mkv": "video/x-matroska",
            ".avi": "video/x-msvideo", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg",
            ".m4a": "audio/mp4", ".flac": "audio/flac",
            ".zip": "application/zip", ".gz": "application/gzip", ".tar": "application/x-tar",
            ".7z": "application/x-7z-compressed"
        ];
    }

    string ofFile(string fileName) {
        if (auto m = fileName.extension.toLower in table)
            return *m;
        return "application/octet-stream";
    }
}
