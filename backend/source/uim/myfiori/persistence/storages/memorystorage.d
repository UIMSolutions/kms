/// Volatile document store (tests, demos). Base class of the file store's cache.
module uim.myfiori.persistence.storages.memorystorage;

import vibe.data.json;
import uim.myfiori.ports.storages : DocumentStorage;

class MemoryStorage : DocumentStorage {
    protected Json[string][string] data; // collection -> id -> document

    Json[] list(string collection) {
        Json[] r;
        if (auto c = collection in data)
            foreach (_, v; *c)
                r ~= v;
        return r;
    }

    Json get(string collection, string id) {
        if (auto c = collection in data)
            if (auto v = id in *c)
                return *v;
        return Json.undefined;
    }

    void put(string collection, string id, Json doc) {
        data[collection][id] = doc;
        written(collection, id, doc);
    }

    bool remove(string collection, string id) {
        if (auto c = collection in data)
            if (id in *c) {
                (*c).remove(id);
                removed(collection, id);
                return true;
            }
        return false;
    }

    size_t count(string collection) {
        if (auto c = collection in data)
            return c.length;
        return 0;
    }

    void flush() {
    }

    protected void written(string collection, string id, Json doc) {
    }

    protected void removed(string collection, string id) {
    }
}
