/// Text extraction for the search engine:
///  - plain text formats (txt, md, csv, json, yaml, log ...), HTML / XML (tags stripped)
///  - Office Open XML (docx, pptx, xlsx) and OpenDocument (odt, odp, ods) via std.zip
///  - PDF via the external `pdftotext` tool (poppler-utils), if installed
module uim.myfiori.infrastructure.clients.textextractor;

import std.algorithm : canFind, filter, map, sort, startsWith, endsWith;
import std.array : appender, array, replace;
import std.conv : to;
import std.file : exists, remove, tempDir, write;
import std.path : buildPath, extension;
import std.string : strip;
import std.uni : toLower;
import std.utf : validate, UTFException;
import std.zip : ZipArchive;
import vibe.core.log;
import uim.myfiori.ports.gateways : TextExtractor;

final class CompositeTextExtractor : TextExtractor {
    private string pdftotext;
    private uint timeoutSeconds;

    this(string pdftotext = "pdftotext", uint timeoutSeconds = 60) {
        this.pdftotext = pdftotext;
        this.timeoutSeconds = timeoutSeconds;
    }

    string extract(string fileName, string mimeType, const(ubyte)[] data) {
        auto ext = fileName.extension.toLower;
        auto m = mimeType.toLower;
        switch (ext) {
        case ".txt", ".md", ".markdown", ".csv", ".tsv", ".json", ".yaml", ".yml", ".log", ".ini", ".conf",
            ".d", ".js", ".ts", ".py", ".java", ".c", ".h", ".cpp", ".sql", ".sh":
            return normalizeWhitespace(toUtf8(data));
        case ".html", ".htm", ".xml", ".svg":
            return normalizeWhitespace(stripTags(toUtf8(data)));
        case ".rtf":
            return normalizeWhitespace(stripRtf(toUtf8(data)));
        case ".docx":
            return fromZip(data, (string n) => n == "word/document.xml" || n.startsWith("word/footnotes"));
        case ".pptx":
            return fromZip(data, (string n) => n.startsWith("ppt/slides/slide") && n.endsWith(".xml"));
        case ".xlsx":
            return fromZip(data, (string n) => n == "xl/sharedStrings.xml");
        case ".odt", ".odp", ".ods":
            return fromZip(data, (string n) => n == "content.xml");
        case ".pdf":
            return fromPdf(data);
        default:
            if (m.startsWith("text/"))
                return normalizeWhitespace(toUtf8(data));
            return "";
        }
    }

    private string fromZip(const(ubyte)[] data, bool delegate(string) wanted) {
        auto zip = new ZipArchive(cast(void[]) data.dup);
        auto names = zip.directory.keys.filter!(n => wanted(n)).array;
        names.sort!((a, b) => naturalLess(a, b));
        auto o = appender!string;
        foreach (n; names) {
            auto member = zip.directory[n];
            if (member.expandedSize > 50 * 1024 * 1024)
                continue; // zip bomb guard
            auto xml = cast(string) zip.expand(member);
            // paragraph / cell ends become line breaks
            xml = xml.replace("</w:p>", "\n").replace("</a:p>", "\n").replace("</text:p>", "\n")
                .replace("</si>", "\n").replace("<w:tab/>", " ");
            o ~= stripTags(xml);
            o ~= "\n";
        }
        return normalizeWhitespace(o[]);
    }

    private string fromPdf(const(ubyte)[] data) {
        if (pdftotext.length == 0)
            return "";
        import std.uuid : randomUUID;
        import vibe.core.process : execute, Config;
        auto tmp = buildPath(tempDir, "kms-" ~ randomUUID.toString ~ ".pdf");
        write(tmp, data);
        scope (exit)
            if (tmp.exists)
                remove(tmp);
        string[] cmd = [pdftotext, "-q", "-enc", "UTF-8", tmp, "-"];
        if ("/usr/bin/timeout".exists)
            cmd = ["/usr/bin/timeout", timeoutSeconds.to!string] ~ cmd;
        try {
            auto r = execute(cmd, null, Config.none, 16 * 1024 * 1024);
            if (r.status != 0) {
                logDiagnostic("pdftotext exit status %s", r.status);
                return "";
            }
            return normalizeWhitespace(toUtf8(cast(const(ubyte)[]) r.output));
        } catch (Exception e) {
            logWarn("pdftotext not available (%s) - PDF content is not searchable", e.msg);
            pdftotext = ""; // do not retry on every upload
            return "";
        }
    }
}

private bool naturalLess(string a, string b) {
    // slide2.xml < slide10.xml
    import std.ascii : isDigit;
    size_t num(string s) {
        size_t v = 0;
        foreach (c; s)
            if (isDigit(c))
                v = v * 10 + (c - '0');
        return v;
    }

    return a.length != b.length ? a.length < b.length : (num(a) != num(b) ? num(a) < num(b) : a < b);
}

/// Interprets bytes as UTF-8, falling back to Latin-1 for invalid input; drops a BOM.
string toUtf8(const(ubyte)[] data) {
    auto s = cast(string) data.idup;
    if (s.startsWith("\xEF\xBB\xBF"))
        s = s[3 .. $];
    try {
        validate(s);
        return s;
    } catch (UTFException) {
        auto o = appender!string;
        foreach (ubyte b; data)
            o.put(cast(dchar) b);
        return o[];
    }
}

/// Removes tags, comments, scripts and styles; decodes the common entities.
string stripTags(string s) {
    auto o = appender!string;
    size_t i = 0;
    auto lower = asciiLower(s);
    while (i < s.length) {
        if (s[i] == '<') {
            foreach (block; ["script", "style"])
                if (lower[i + 1 .. $].startsWith(block)) {
                    import std.string : indexOf;
                    auto end = lower[i .. $].indexOf("</" ~ block);
                    if (end > 0)
                        i += end;
                }
            if (s[i .. $].startsWith("<!--")) {
                import std.string : indexOf;
                auto end = s[i .. $].indexOf("-->");
                i = end < 0 ? s.length : i + end + 3;
                continue;
            }
            while (i < s.length && s[i] != '>')
                i++;
            i++;
            o ~= ' ';
            continue;
        }
        o ~= s[i];
        i++;
    }
    return o[].replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
        .replace("&#39;", "'").replace("&apos;", "'").replace("&amp;", "&");
}

private string stripRtf(string s) {
    auto o = appender!string;
    size_t i = 0;
    while (i < s.length) {
        auto c = s[i];
        if (c == '\\') {
            i++;
            while (i < s.length && ((s[i] >= 'a' && s[i] <= 'z') || s[i] == '-' || (s[i] >= '0' && s[i] <= '9')))
                i++;
            if (i < s.length && s[i] == ' ')
                i++;
            continue;
        }
        if (c != '{' && c != '}')
            o ~= c;
        i++;
    }
    return o[];
}

private string asciiLower(string s) {
    import std.ascii : toLower;
    auto b = new char[s.length];
    foreach (i, char c; s)
        b[i] = toLower(c);
    return cast(string) b;
}

/// Collapses runs of spaces / tabs, keeps single line breaks.
string normalizeWhitespace(string s) {
    auto o = appender!string;
    bool space = false, nl = false;
    foreach (char c; s) {
        if (c == '\r')
            continue;
        if (c == '\n') {
            if (!nl)
                o ~= '\n';
            nl = true;
            space = false;
            continue;
        }
        if (c == ' ' || c == '\t' || c == '\f' || c == '\v') {
            space = true;
            continue;
        }
        if (space && !nl)
            o ~= ' ';
        space = false;
        nl = false;
        o ~= c;
    }
    return o[].strip;
}

unittest {
    auto x = new CompositeTextExtractor("");
    assert(x.extract("a.txt", "", cast(const(ubyte)[]) "Hello   world\r\n\r\nagain") == "Hello world\nagain");
    assert(x.extract("a.html", "", cast(const(ubyte)[]) "<p>Fish &amp; chips</p><script>x()</script>") == "Fish & chips");
    assert(toUtf8([0x47, 0xFC]) == "Gü");
    // a minimal docx
    import std.zip : ArchiveMember;
    auto zip = new ZipArchive;
    auto m = new ArchiveMember;
    m.name = "word/document.xml";
    m.expandedData = cast(ubyte[]) `<w:document><w:p><w:r><w:t>Quarterly report</w:t></w:r></w:p></w:document>`.dup;
    zip.addMember(m);
    auto bytes = cast(ubyte[]) zip.build();
    assert(x.extract("r.docx", "", bytes) == "Quarterly report");
}
