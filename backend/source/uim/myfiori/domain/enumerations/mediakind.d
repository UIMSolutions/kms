/// Classification of uploaded files (documents and other media).
module uim.myfiori.domain.enumerations.mediakind;

import std.algorithm.searching : canFind, startsWith;
import std.path : extension;
import std.uni : toLower;

enum MediaKind {
    document,
    spreadsheet,
    presentation,
    image,
    video,
    audio,
    archive,
    other
}

string kindName(MediaKind k) pure @safe {
    final switch (k) {
    case MediaKind.document:
        return "document";
    case MediaKind.spreadsheet:
        return "spreadsheet";
    case MediaKind.presentation:
        return "presentation";
    case MediaKind.image:
        return "image";
    case MediaKind.video:
        return "video";
    case MediaKind.audio:
        return "audio";
    case MediaKind.archive:
        return "archive";
    case MediaKind.other:
        return "other";
    }
}

/// Derives the kind from MIME type and file name.
MediaKind classify(string mimeType, string fileName) @safe {
    auto m = mimeType.toLower;
    auto ext = fileName.extension.toLower;
    if (m.startsWith("image/"))
        return MediaKind.image;
    if (m.startsWith("video/"))
        return MediaKind.video;
    if (m.startsWith("audio/"))
        return MediaKind.audio;
    if ([".xls", ".xlsx", ".ods", ".csv"].canFind(ext))
        return MediaKind.spreadsheet;
    if ([".ppt", ".pptx", ".odp", ".key"].canFind(ext))
        return MediaKind.presentation;
    if ([".zip", ".tar", ".gz", ".tgz", ".7z", ".rar", ".bz2", ".xz"].canFind(ext))
        return MediaKind.archive;
    if ([".pdf", ".doc", ".docx", ".odt", ".rtf", ".txt", ".md", ".html", ".htm", ".xml", ".json", ".log"].canFind(ext)
            || m.startsWith("text/"))
        return MediaKind.document;
    return MediaKind.other;
}

unittest {
    assert(classify("image/png", "a.png") == MediaKind.image);
    assert(classify("application/octet-stream", "Q3.xlsx") == MediaKind.spreadsheet);
    assert(classify("application/pdf", "manual.pdf") == MediaKind.document);
    assert(classify("", "x.bin") == MediaKind.other);
}
