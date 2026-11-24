/// Knowledge articles: CRUD, lifecycle (draft -> published -> archived), version history.
module uim.myfiori.application.usecases.articleusecases;

import std.algorithm : canFind, filter, sort;
import std.array : array;
import std.conv : to;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

enum maxVersionsKept = 50;

final class ArticleInteractor : ArticleUseCase {
    private ArticleRepository articles;
    private ArticleVersionRepository history;
    private SpaceRepository spaces;
    private DocumentRepository documents;
    private SearchIndexer indexer;
    private AccessResolver resolver;
    private Clock clock;
    private IdGenerator ids;
    private EventPublisher events;
    private DtoMapper mapper;

    this(ArticleRepository articles, ArticleVersionRepository history, SpaceRepository spaces,
        DocumentRepository documents, SearchIndexer indexer, AccessResolver resolver, Clock clock, IdGenerator ids,
        EventPublisher events, DtoMapper mapper) {
        this.resolver = resolver;
        this.articles = articles;
        this.history = history;
        this.spaces = spaces;
        this.documents = documents;
        this.indexer = indexer;
        this.clock = clock;
        this.ids = ids;
        this.events = events;
        this.mapper = mapper;
    }

    Page!ArticleDto list(in Principal p, ArticleFilter f) {
        auto access = resolver.resolve(p);
        auto text = f.text.strip.toLower;
        auto tag = f.tag.strip.toLower;
        string[] areas;
        if (f.spaceId.length)
            areas = [f.spaceId] ~ (f.includeSubAreas ? access.tree.descendants(f.spaceId) : null);
        auto all = articles.all().filter!((a) {
            if (areas.length && !areas.canFind(a.spaceId))
                return false;
            if (!access.canReadArticle(a))
                return false;
            if (f.status.length && statusName(a.status) != f.status)
                return false;
            if (tag.length && !a.tags.canFind(tag))
                return false;
            if (f.authorId.length && a.authorId != f.authorId)
                return false;
            if (text.length && !a.title.toLower.canFind(text) && !a.summary.toLower.canFind(text))
                return false;
            return true;
        }).array;
        switch (f.orderBy) {
        case "title":
            all.sort!((a, b) => a.title.toLower < b.title.toLower);
            break;
        case "views desc":
            all.sort!((a, b) => a.views > b.views);
            break;
        case "createdAt desc":
            all.sort!((a, b) => a.createdAt > b.createdAt);
            break;
        default:
            all.sort!((a, b) => a.updatedAt > b.updatedAt);
        }
        Page!ArticleDto r;
        r.total = all.length;
        foreach (a; slicePage(all, f.skip, f.top))
            r.items ~= mapper.article(a, access, f.withBody);
        return r;
    }

    ArticleDto get(in Principal p, string id, bool countView = false) {
        auto access = resolver.resolve(p);
        auto a = readable(access, id);
        if (countView) {
            a.views++;
            articles.save(a);
        }
        return mapper.article(a, access);
    }

    ArticleDto create(in Principal p, ArticleInput input) {
        auto access = resolver.resolve(p);
        auto a = new Article;
        a.id = ids.newId;
        a.authorId = p.userId;
        a.createdAt = clock.now;
        apply(access, a, input, true);
        a.updatedBy = p.userId;
        a.updatedAt = a.createdAt;
        articles.save(a);
        indexer.index(a);
        events.publish(DomainEvent("article.created", a.id, p.userId, a.title, clock.now));
        return mapper.article(a, access);
    }

    ArticleDto update(in Principal p, string id, ArticleInput input, long expectedVersion = 0) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireWrite(a.spaceId);
        checkVersion(a, expectedVersion);
        snapshot(a, p.userId);
        apply(access, a, input, false);
        touch(a, p);
        events.publish(DomainEvent("article.updated", a.id, p.userId, a.title, clock.now));
        return mapper.article(a, access);
    }

    ArticleDto publish(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireWrite(a.spaceId);
        snapshot(a, p.userId);
        a.publish(clock.now);
        touch(a, p);
        events.publish(DomainEvent("article.published", a.id, p.userId, a.title, clock.now));
        return mapper.article(a, access);
    }

    ArticleDto archive(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireWrite(a.spaceId);
        snapshot(a, p.userId);
        a.archive();
        touch(a, p);
        events.publish(DomainEvent("article.archived", a.id, p.userId, a.title, clock.now));
        return mapper.article(a, access);
    }

    ArticleDto reopen(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireWrite(a.spaceId);
        if (a.status == ArticleStatus.draft)
            throw new ConflictException("Article is already a draft");
        snapshot(a, p.userId);
        a.reopen();
        touch(a, p);
        return mapper.article(a, access);
    }

    ArticleVersionDto[] versions(in Principal p, string id) {
        auto access = resolver.resolve(p);
        access.requireWrite(require(id).spaceId);
        ArticleVersionDto[] r;
        foreach (v; history.byArticle(id))
            r ~= mapper.articleVersion(v);
        return r;
    }

    ArticleDto restore(in Principal p, string id, string versionId) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireWrite(a.spaceId);
        auto v = history.byId(versionId);
        if (v is null || v.articleId != a.id)
            throw new NotFoundException("Version not found");
        snapshot(a, p.userId);
        a.title = v.title;
        a.summary = v.summary;
        a.body = v.body;
        a.tags = v.tags.dup;
        touch(a, p);
        events.publish(DomainEvent("article.restored", a.id, p.userId, "v" ~ v.version_.to!string, clock.now));
        return mapper.article(a, access);
    }

    void remove(in Principal p, string id) {
        auto access = resolver.resolve(p);
        auto a = require(id);
        access.requireDelete(a.spaceId, a.authorId);
        articles.remove(a.id);
        history.removeByArticle(a.id);
        indexer.remove(a.id);
        events.publish(DomainEvent("article.deleted", a.id, p.userId, a.title, clock.now));
    }

    // ------------------------------------------------------------------ helpers

    private Article require(string id) {
        auto a = articles.byId(id);
        if (a is null)
            throw new NotFoundException("Article not found");
        return a;
    }

    private Article readable(in SpaceAccess access, string id) {
        auto a = require(id);
        if (!access.canReadArticle(a))
            throw new NotFoundException("Article not found"); // do not reveal drafts
        return a;
    }

    private void checkVersion(Article a, long expected) {
        if (expected > 0 && expected != a.version_)
            throw new ConflictException("The article was changed by someone else (version "
                    ~ a.version_.to!string ~ ") - reload and try again");
    }

    private void apply(in SpaceAccess access, Article a, ArticleInput input, bool creating) {
        if (!input.spaceId.isNull && input.spaceId.get != a.spaceId) {
            if (spaces.byId(input.spaceId.get) is null)
                throw new ValidationException("Unknown area");
            access.requireWrite(input.spaceId.get); // also when moving to another area
            a.spaceId = input.spaceId.get;
        } else if (creating)
            throw new ValidationException("Area is required");
        if (!input.title.isNull)
            a.title = input.title.get.strip;
        if (!input.summary.isNull) {
            if (input.summary.get.length > 1000)
                throw new ValidationException("Summary too long (max 1000 characters)");
            a.summary = input.summary.get.strip;
        }
        if (!input.body.isNull)
            a.body = input.body.get;
        if (!input.tags.isNull)
            a.tags = normalizeTags(input.tags.get);
        if (!input.attachmentIds.isNull) {
            string[] ids;
            foreach (id; input.attachmentIds.get) {
                auto doc = documents.byId(id);
                if (doc is null || !access.canRead(doc.spaceId))
                    throw new ValidationException("Unknown attachment " ~ id);
                if (!ids.canFind(id))
                    ids ~= id;
            }
            a.attachmentIds = ids;
        }
        validateArticleText(a.title, a.body);
    }

    private void touch(Article a, in Principal p) {
        a.updatedBy = p.userId;
        a.updatedAt = clock.now;
        a.version_++;
        articles.save(a);
        indexer.index(a);
    }

    private void snapshot(Article a, string userId) {
        auto v = new ArticleVersion;
        v.id = ids.newId;
        v.articleId = a.id;
        v.version_ = a.version_;
        v.title = a.title;
        v.summary = a.summary;
        v.body = a.body;
        v.tags = a.tags.dup;
        v.status = statusName(a.status);
        v.changedBy = a.updatedBy.length ? a.updatedBy : userId;
        v.changedAt = a.updatedAt;
        history.save(v);
        // keep the history bounded
        auto all = history.byArticle(a.id);
        if (all.length > maxVersionsKept) {
            foreach (old; all[maxVersionsKept .. $])
                history.remove(old.id);
        }
    }
}
