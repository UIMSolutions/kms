/// Durable document store on the file system:
///
///     <dataDir>/db/<collection>/<id>.json
///
/// One pretty-printed JSON file per entity, written atomically (temp file + rename), so
/// the data stays human readable, diff-able and easy to back up (`tar`, `rsync`, git).
/// All documents are cached in memory and loaded at start-up.
module uim.myfiori.persistence.storages.filedocumentstorage;

import std.algorithm.searching : all, endsWith;
import std.ascii : isAlphaNum;
import std.file : dirEntries, exists, isDir, mkdirRecurse, readText, remove, rename, SpanMode, write;
import std.path : baseName, buildPath, stripExtension;
static import std.file;
import vibe.core.log;
import vibe.data.json;
import uim.myfiori.persistence.storages.memorystorage;

final class FileDocumentStorage : MemoryStorage {
    private string root;

    this(string dataDir) {
        root = buildPath(dataDir, "db");
        if (!root.exists)
            mkdirRecurse(root);
        foreach (dir; dirEntries(root, SpanMode.shallow)) {
            if (!dir.isDir)
                continue;
            auto collection = dir.name.baseName;
            size_t n;
            foreach (f; dirEntries(dir.name, "*.json", SpanMode.shallow)) {
                try {
                    auto doc = parseJsonString(readText(f.name), f.name);
                    if (doc.type == Json.Type.object) {
                        data[collection][f.name.baseName.stripExtension] = doc;
                        n++;
                    }
                } catch (Exception e)
                    logError("storage: skipping unreadable %s: %s", f.name, e.msg);
            }
            logInfo("storage: loaded %s %s", n, collection);
        }
    }

    protected override void written(string collection, string id, Json doc) {
        checkName(collection);
        checkName(id);
        auto dir = buildPath(root, collection);
        if (!dir.exists)
            mkdirRecurse(dir);
        auto target = buildPath(dir, id ~ ".json");
        auto tmp = target ~ ".tmp";
        write(tmp, doc.toPrettyString);
        rename(tmp, target);
    }

    protected override void removed(string collection, string id) {
        checkName(collection);
        checkName(id);
        auto target = buildPath(root, collection, id ~ ".json");
        if (target.exists)
            std.file.remove(target);
    }

    /// ids and collection names become file names: no path tricks
    private static void checkName(string n) {
        if (n.length == 0 || n.length > 128 || !n.all!(c => c < 0x80 && (isAlphaNum(cast(char) c) || c == '-' || c == '_')))
            throw new Exception("invalid storage key: " ~ n);
    }
}

unittest {
    import std.file : rmdirRecurse, tempDir;
    import std.uuid : randomUUID;
    auto dir = buildPath(tempDir, "kms-test-" ~ randomUUID.toString);
    scope (exit)
        if (dir.exists)
            rmdirRecurse(dir);
    auto s = new FileDocumentStorage(dir);
    s.put("users", "u1", Json(["name": Json("anna")]));
    s.put("users", "u2", Json(["name": Json("ben")]));
    s.remove("users", "u2");
    auto reloaded = new FileDocumentStorage(dir);
    assert(reloaded.count("users") == 1);
    assert(reloaded.get("users", "u1")["name"].get!string == "anna");
    bool thrown;
    try
        s.put("users", "../x", Json.emptyObject);
    catch (Exception)
        thrown = true;
    assert(thrown);
}
