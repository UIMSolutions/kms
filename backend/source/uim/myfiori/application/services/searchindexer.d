/// Keeps the search engine in sync with articles and documents.
module uim.myfiori.application.services.searchindexer;

import vibe.core.log;
import uim.myfiori.application.services.dtomapper : iso;
import uim.myfiori.domain;
import uim.myfiori.ports.repositories;

final class SearchIndexer {
    SearchEngine engine;

    this(SearchEngine engine) {
        this.engine = engine;
    }

    void index(Article a) {
        IndexEntry e;
        e.id = a.id;
        e.kind = ItemKind.article;
        e.title = a.title;
        e.text = a.body;
        e.summary = a.summary;
        e.tags = a.tags.dup;
        e.spaceId = a.spaceId;
        e.status = statusName(a.status);
        e.updatedAt = iso(a.updatedAt);
        e.ownerId = a.authorId;
        engine.put(e);
    }

    void index(Document d) {
        IndexEntry e;
        e.id = d.id;
        e.kind = ItemKind.document;
        e.title = d.title.length ? d.title : d.fileName;
        // the file name and description are searchable too
        e.summary = d.description ~ " " ~ d.fileName;
        e.text = d.text;
        e.tags = d.tags.dup;
        e.spaceId = d.spaceId;
        e.status = "published";
        e.mediaKind = kindName(d.kind);
        e.updatedAt = iso(d.updatedAt);
        e.ownerId = d.uploadedBy;
        engine.put(e);
    }

    void remove(string id) {
        engine.remove(id);
    }

    /// Rebuilds the whole index from the repositories (start-up / admin "reindex").
    size_t rebuild(ArticleRepository articles, DocumentRepository documents) {
        engine.clear();
        foreach (a; articles.all())
            index(a);
        foreach (d; documents.all())
            index(d);
        logInfo("search: indexed %s items, %s distinct terms", engine.count, engine.vocabularySize);
        return engine.count;
    }
}
