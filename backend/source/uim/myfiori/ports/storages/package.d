/// Driven ports for low-level data stores (implemented in persistence/storages).
module uim.myfiori.ports.storages;

import vibe.data.json : Json;

/// Schemaless document store: collections of JSON documents addressed by id.
interface DocumentStorage {
    Json[] list(string collection);
    Json get(string collection, string id); /// Json.undefined if missing
    void put(string collection, string id, Json doc);
    bool remove(string collection, string id);
    size_t count(string collection);
    void flush();
}

struct BlobInfo {
    string key;
    ulong size;
    string sha256;
}

/// Binary content store (files of documents and media).
interface BlobStorage {
    /// Stores `data` under a new or existing key; returns size and checksum.
    BlobInfo put(string key, const(ubyte)[] data);
    /// Reads the whole blob (throws NotFoundException).
    ubyte[] get(string key);
    /// Absolute file system path for streaming, or null if the store is not file based.
    string localPath(string key);
    bool exists(string key);
    void remove(string key);
    /// total bytes stored
    ulong usedBytes();
}
