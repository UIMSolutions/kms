/// Binary storage for documents and media on the file system:
///
///     <dataDir>/files/<k0k1>/<key>
///
/// (two-character fan-out directories keep directory sizes small). Writes are atomic.
/// MemoryBlobStorage is the volatile variant for tests.
module uim.myfiori.persistence.storages.fileblobstorage;

import std.algorithm.searching : all;
import std.ascii : isAlphaNum;
import std.digest : toHexString, LetterCase;
import std.digest.sha : sha256Of;
import std.file : dirEntries, exists, getSize, mkdirRecurse, read, remove, rename, SpanMode, write;
import std.path : buildPath;
static import std.file;
import uim.myfiori.domain.exceptions : NotFoundException;
import uim.myfiori.ports.storages : BlobInfo, BlobStorage;

string sha256Hex(const(ubyte)[] data) {
    return sha256Of(data).toHexString!(LetterCase.lower).idup;
}

final class FileBlobStorage : BlobStorage {
    private string root;
    private ulong used;

    this(string dataDir) {
        root = buildPath(dataDir, "files");
        if (!root.exists)
            mkdirRecurse(root);
        foreach (e; dirEntries(root, SpanMode.depth))
            if (e.isFile && !(e.name.length > 4 && e.name[$ - 4 .. $] == ".tmp"))
                used += e.size;
    }

    BlobInfo put(string key, const(ubyte)[] data) {
        auto path = pathOf(key);
        auto dir = buildPath(root, key[0 .. 2]);
        if (!dir.exists)
            mkdirRecurse(dir);
        if (path.exists)
            used -= getSize(path);
        auto tmp = path ~ ".tmp";
        write(tmp, data);
        rename(tmp, path);
        used += data.length;
        return BlobInfo(key, data.length, sha256Hex(data));
    }

    ubyte[] get(string key) {
        auto path = pathOf(key);
        if (!path.exists)
            throw new NotFoundException("File content not found");
        return cast(ubyte[]) read(path);
    }

    string localPath(string key) {
        return pathOf(key);
    }

    bool exists(string key) {
        return pathOf(key).exists;
    }

    void remove(string key) {
        auto path = pathOf(key);
        if (path.exists) {
            used -= getSize(path);
            std.file.remove(path);
        }
    }

    ulong usedBytes() {
        return used;
    }

    private string pathOf(string key) {
        if (key.length < 3 || key.length > 128 || !key.all!(c => c < 0x80 && (isAlphaNum(cast(char) c) || c == '-')))
            throw new Exception("invalid blob key");
        return buildPath(root, key[0 .. 2], key);
    }
}

final class MemoryBlobStorage : BlobStorage {
    private ubyte[][string] blobs;

    BlobInfo put(string key, const(ubyte)[] data) {
        blobs[key] = data.dup;
        return BlobInfo(key, data.length, sha256Hex(data));
    }

    ubyte[] get(string key) {
        if (auto b = key in blobs)
            return (*b).dup;
        throw new NotFoundException("File content not found");
    }

    string localPath(string key) {
        return null;
    }

    bool exists(string key) {
        return (key in blobs) !is null;
    }

    void remove(string key) {
        blobs.remove(key);
    }

    ulong usedBytes() {
        ulong n;
        foreach (_, b; blobs)
            n += b.length;
        return n;
    }
}

unittest {
    import std.file : rmdirRecurse, tempDir;
    import std.uuid : randomUUID;
    auto dir = buildPath(tempDir, "kms-blob-" ~ randomUUID.toString);
    scope (exit)
        if (dir.exists)
            rmdirRecurse(dir);
    auto s = new FileBlobStorage(dir);
    auto info = s.put("abc-123", cast(const(ubyte)[]) "hello");
    assert(info.size == 5 && info.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    assert(s.usedBytes == 5 && cast(string) s.get("abc-123") == "hello");
    s.put("abc-123", cast(const(ubyte)[]) "hi");
    assert(s.usedBytes == 2);
    assert(new FileBlobStorage(dir).usedBytes == 2);
    s.remove("abc-123");
    assert(!s.exists("abc-123") && s.usedBytes == 0);
}
