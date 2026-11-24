/// Knowledge spaces (read: everybody, write: administrators).
module uim.myfiori.application.usecases.spaceusecases;

import std.algorithm : count, sort;
import std.string : strip;
import uim.myfiori.application.dtos;
import uim.myfiori.application.services;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class SpaceInteractor : SpaceUseCase {
    private SpaceRepository spaces;
    private ArticleRepository articles;
    private DocumentRepository documents;
    private Clock clock;
    private IdGenerator ids;
    private EventPublisher events;
    private DtoMapper mapper;

    this(SpaceRepository spaces, ArticleRepository articles, DocumentRepository documents, Clock clock,
        IdGenerator ids, EventPublisher events, DtoMapper mapper) {
        this.spaces = spaces;
        this.articles = articles;
        this.documents = documents;
        this.clock = clock;
        this.ids = ids;
        this.events = events;
        this.mapper = mapper;
    }

    SpaceDto[] list(in Principal p) {
        auto all = spaces.all();
        all.sort!((a, b) => a.name < b.name);
        SpaceDto[] r;
        foreach (s; all)
            r ~= toDto(p, s);
        return r;
    }

    SpaceDto get(in Principal p, string id) {
        return toDto(p, require(id));
    }

    SpaceDto create(in Principal p, SpaceInput input) {
        AccessPolicy.requireAdmin(p);
        if (input.key.isNull || input.name.isNull || input.name.get.strip.length == 0)
            throw new ValidationException("Key and name are required");
        auto key = validSpaceKey(input.key.get);
        if (spaces.byKey(key) !is null)
            throw new ConflictException("Space key already exists: " ~ key);
        const now = clock.now;
        auto s = new Space;
        s.id = ids.newId;
        s.key = key;
        s.name = input.name.get.strip;
        if (!input.description.isNull)
            s.description = input.description.get;
        if (!input.icon.isNull && input.icon.get.length)
            s.icon = input.icon.get;
        s.createdBy = p.userId;
        s.createdAt = s.updatedAt = now;
        spaces.save(s);
        events.publish(DomainEvent("space.created", s.id, p.userId, s.key, now));
        return toDto(p, s);
    }

    SpaceDto update(in Principal p, string id, SpaceInput input) {
        AccessPolicy.requireAdmin(p);
        auto s = require(id);
        if (!input.key.isNull) {
            auto key = validSpaceKey(input.key.get);
            auto other = spaces.byKey(key);
            if (other !is null && other.id != s.id)
                throw new ConflictException("Space key already exists: " ~ key);
            s.key = key;
        }
        if (!input.name.isNull) {
            if (input.name.get.strip.length == 0)
                throw new ValidationException("Name is required");
            s.name = input.name.get.strip;
        }
        if (!input.description.isNull)
            s.description = input.description.get;
        if (!input.icon.isNull && input.icon.get.length)
            s.icon = input.icon.get;
        s.updatedAt = clock.now;
        s.version_++;
        spaces.save(s);
        return toDto(p, s);
    }

    void remove(in Principal p, string id) {
        AccessPolicy.requireAdmin(p);
        auto s = require(id);
        if (articles.bySpace(s.id).length || documents.bySpace(s.id).length)
            throw new ConflictException("Space is not empty - move or delete its articles and documents first");
        spaces.remove(s.id);
        events.publish(DomainEvent("space.deleted", s.id, p.userId, s.key, clock.now));
    }

    private Space require(string id) {
        auto s = spaces.byId(id);
        if (s is null)
            throw new NotFoundException("Space not found");
        return s;
    }

    private SpaceDto toDto(in Principal p, Space s) {
        import std.algorithm : filter;
        import std.range : walkLength;
        auto arts = articles.bySpace(s.id).filter!(a => AccessPolicy.canReadArticle(p, a)).walkLength;
        return mapper.space(s, arts, documents.bySpace(s.id).length);
    }
}
