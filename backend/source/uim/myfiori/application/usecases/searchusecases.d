/// Full-text search across articles and documents, with permission-aware results.
module uim.myfiori.application.usecases.searchusecases;

import std.string : strip;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class SearchInteractor : SearchUseCase {
    private SearchIndexer indexer;
    private AccessResolver resolver;
    private ArticleRepository articles;
    private DocumentRepository documents;
    private DtoMapper mapper;
    private EventPublisher events;
    private Clock clock;

    this(SearchIndexer indexer, AccessResolver resolver, ArticleRepository articles, DocumentRepository documents,
        DtoMapper mapper, EventPublisher events, Clock clock) {
        this.resolver = resolver;
        this.indexer = indexer;
        this.articles = articles;
        this.documents = documents;
        this.mapper = mapper;
        this.events = events;
        this.clock = clock;
    }

    SearchResultDto search(in Principal p, SearchQuery q) {
        if (q.text.length > 500)
            throw new ValidationException("Query too long");
        if (q.top > 200)
            q.top = 200;
        auto access = resolver.resolve(p);
        auto tree = access.tree;
        auto r = indexer.engine.search(q, (ref const IndexEntry e) => access.canReadStatus(e.spaceId, e.status));
        SearchResultDto d;
        d.query = q.text;
        d.total = r.total;
        d.suggestions = r.suggestions.dup;
        d.tookMs = r.tookMicros / 1000.0;
        foreach (h; r.hits)
            d.hits ~= SearchHitDto(h.id, cast(string) h.kind, h.title, h.snippet, h.score, h.spaceId,
                tree.path(h.spaceId), h.tags.dup, h.status, h.mediaKind, h.updatedAt);
        foreach (f; r.kinds)
            d.kinds ~= FacetDto(f.value, f.value, f.count);
        foreach (f; r.spaces)
            d.spaces ~= FacetDto(f.value, tree.path(f.value), f.count);
        foreach (f; r.tags)
            d.tags ~= FacetDto(f.value, f.value, f.count);
        foreach (f; r.mediaKinds)
            d.mediaKinds ~= FacetDto(f.value, f.value, f.count);
        if (q.text.strip.length)
            events.publish(DomainEvent("search.query", "", p.userId, q.text, clock.now));
        return d;
    }

    string[] suggest(in Principal p, string prefix) {
        auto access = resolver.resolve(p);
        return indexer.engine.suggest(prefix, 8, (ref const IndexEntry e) => access.canReadStatus(e.spaceId, e.status));
    }

    size_t reindex(in Principal p) {
        AccessPolicy.requireAdmin(p);
        return indexer.rebuild(articles, documents);
    }
}
