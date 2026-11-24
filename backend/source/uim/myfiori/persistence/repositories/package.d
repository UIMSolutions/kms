/// Repository implementations on top of the DocumentStorage port. Work with both the
/// file system store (production) and the memory store (tests).
module uim.myfiori.persistence.repositories;

import std.algorithm : filter, sort;
import std.array : array;
import vibe.data.json;
import uim.myfiori.domain.entities;
import uim.myfiori.persistence.mappers;
import uim.myfiori.persistence.records;
import uim.myfiori.ports.repositories;
import uim.myfiori.ports.storages;

/// Generic CRUD over one collection.
private mixin template StorageCrud(Entity, Record, string collection) {
    private DocumentStorage storage;

    this(DocumentStorage storage) {
        this.storage = storage;
    }

    Entity[] all() {
        Entity[] r;
        foreach (j; storage.list(collection))
            r ~= toEntity(deserializeJson!Record(j));
        return r;
    }

    Entity byId(string id) {
        if (id.length == 0)
            return null;
        auto j = storage.get(collection, id);
        return j.type == Json.Type.undefined ? null : toEntity(deserializeJson!Record(j));
    }

    void save(Entity e) {
        storage.put(collection, e.id, serializeToJson(toRecord(e)));
    }

    void remove(string id) {
        storage.remove(collection, id);
    }
}

final class StorageUserRepository : UserRepository {
    mixin StorageCrud!(User, UserRecord, Collections.users);

    User byUsername(string name) {
        foreach (u; all())
            if (u.username == name)
                return u;
        return null;
    }

    User byExternalId(string ext) {
        if (ext.length == 0)
            return null;
        foreach (u; all())
            if (u.externalId == ext)
                return u;
        return null;
    }

    size_t count() {
        return storage.count(Collections.users);
    }
}

final class StorageSpaceRepository : SpaceRepository {
    mixin StorageCrud!(Space, SpaceRecord, Collections.spaces);

    Space byKey(string key) {
        foreach (s; all())
            if (s.key == key)
                return s;
        return null;
    }
}

final class StorageArticleRepository : ArticleRepository {
    mixin StorageCrud!(Article, ArticleRecord, Collections.articles);

    Article[] bySpace(string spaceId) {
        return all().filter!(a => a.spaceId == spaceId).array;
    }
}

final class StorageArticleVersionRepository : ArticleVersionRepository {
    mixin StorageCrud!(ArticleVersion, ArticleVersionRecord, Collections.articleVersions);

    ArticleVersion[] byArticle(string articleId) {
        auto r = all().filter!(v => v.articleId == articleId).array;
        r.sort!((a, b) => a.version_ > b.version_);
        return r;
    }

    void removeByArticle(string articleId) {
        foreach (v; byArticle(articleId))
            remove(v.id);
    }
}

final class StorageDocumentRepository : DocumentRepository {
    mixin StorageCrud!(Document, DocumentRecord, Collections.documents);

    Document[] bySpace(string spaceId) {
        return all().filter!(d => d.spaceId == spaceId).array;
    }
}
