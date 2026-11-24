/// Dashboard figures: counts, storage, index size, top tags, recently changed items.
module uim.myfiori.application.usecases.statisticsusecases;

import std.algorithm : count, min, sort;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class StatisticsInteractor : StatisticsUseCase {
    private UserRepository users;
    private SpaceRepository spaces;
    private ArticleRepository articles;
    private DocumentRepository documents;
    private BlobStorage blobs;
    private SearchIndexer indexer;
    private AccessResolver resolver;
    private DtoMapper mapper;

    this(UserRepository users, SpaceRepository spaces, ArticleRepository articles, DocumentRepository documents,
        BlobStorage blobs, SearchIndexer indexer, AccessResolver resolver, DtoMapper mapper) {
        this.resolver = resolver;
        this.users = users;
        this.spaces = spaces;
        this.articles = articles;
        this.documents = documents;
        this.blobs = blobs;
        this.indexer = indexer;
        this.mapper = mapper;
    }

    StatsDto stats(in Principal p) {
        auto access = resolver.resolve(p);
        StatsDto s;
        s.users = p.isAdmin ? users.count() : 0;
        foreach (id; access.readableSpaceIds()) {
            s.spaces++;
            if (access.canManage(id))
                s.managedSpaces++;
        }
        auto arts = articles.all();
        auto docs = documents.all();
        size_t[string] tags;
        RecentItemDto[] recent;
        foreach (a; arts) {
            if (!access.canReadArticle(a))
                continue;
            s.articles++;
            if (a.status == ArticleStatus.published)
                s.publishedArticles++;
            else if (a.status == ArticleStatus.draft)
                s.draftArticles++;
            foreach (t; a.tags)
                tags[t]++;
            recent ~= RecentItemDto(a.id, "article", a.title, iso(a.updatedAt), mapper.userName(a.updatedBy));
        }
        size_t[string] kinds;
        foreach (d; docs) {
            if (!access.canRead(d.spaceId))
                continue;
            s.documents++;
            kinds[kindName(d.kind)]++;
            foreach (t; d.tags)
                tags[t]++;
            recent ~= RecentItemDto(d.id, "document", d.title, iso(d.updatedAt), mapper.userName(d.updatedBy));
        }
        s.storageBytes = blobs.usedBytes();
        s.indexedItems = indexer.engine.count;
        s.vocabulary = indexer.engine.vocabularySize;
        foreach (k, v; kinds)
            s.mediaKinds ~= CountDto(k, k, v);
        s.mediaKinds.sort!((a, b) => a.count > b.count);
        foreach (k, v; tags)
            s.topTags ~= CountDto(k, k, v);
        s.topTags.sort!((a, b) => a.count > b.count || (a.count == b.count && a.key < b.key));
        s.topTags = s.topTags[0 .. min(15, s.topTags.length)];
        recent.sort!((a, b) => a.updatedAt > b.updatedAt);
        s.recent = recent[0 .. min(10, recent.length)];
        return s;
    }
}
