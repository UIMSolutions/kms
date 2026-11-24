/// Composition root: the only place that knows every concrete class and wires adapters to ports.
module uim.myfiori.composition;

import std.path : buildPath;
import vibe.core.log;
import uim.myfiori.application;
import uim.myfiori.domain;
import uim.myfiori.infrastructure;
import uim.myfiori.persistence;
import uim.myfiori.ports;
import uim.myfiori.presentation;

final class Container {
    AppConfig config;

    // driven adapters
    DocumentStorage storage;
    BlobStorage blobs;
    UserRepository userRepo;
    SpaceRepository spaceRepo;
    ArticleRepository articleRepo;
    ArticleVersionRepository versionRepo;
    MembershipRepository membershipRepo;
    DocumentRepository documentRepo;
    SystemClock clock;
    UuidGenerator ids;
    ExtensionMimeTypes mimeTypes;
    Pbkdf2PasswordHasher hasher;
    HmacTokenIssuer tokens;
    XsuaaTokenValidator xsuaa; // null unless bound
    CompositeTextExtractor extractor;
    EventBus events;
    AuditLog audit;
    RequestMetrics metrics;

    // application
    DtoMapper mapper;
    AccessResolver resolver;
    SearchIndexer indexer;
    TextExtractionService extraction;
    TextExtractionWorker extractionWorker;
    TokenIdentityService identity;
    BootstrapService bootstrap;
    AuthInteractor auth;
    UserInteractor users;
    SpaceInteractor spaces;
    ArticleInteractor articles;
    DocumentInteractor documents;
    SearchInteractor search;
    StatisticsInteractor statistics;

    this(AppConfig config, uint passwordIterations = 210_000, bool synchronousExtraction = false) {
        this.config = config;
        const memory = config.storage.driver == "memory";

        storage = memory ? new MemoryStorage : new FileDocumentStorage(config.storage.dataDir);
        blobs = memory ? cast(BlobStorage) new MemoryBlobStorage : new FileBlobStorage(config.storage.dataDir);
        userRepo = new StorageUserRepository(storage);
        spaceRepo = new StorageSpaceRepository(storage);
        articleRepo = new StorageArticleRepository(storage);
        versionRepo = new StorageArticleVersionRepository(storage);
        membershipRepo = new StorageMembershipRepository(storage);
        documentRepo = new StorageDocumentRepository(storage);

        clock = new SystemClock;
        ids = new UuidGenerator;
        mimeTypes = new ExtensionMimeTypes;
        hasher = new Pbkdf2PasswordHasher(passwordIterations);
        auto secret = config.auth.tokenSecret;
        if (secret.length == 0) {
            secret = randomSecret(32);
            logWarn("auth.tokenSecret / KMS_TOKEN_SECRET not set: generated an ephemeral secret "
                    ~ "(sessions end on restart and are not shared between instances)");
        }
        tokens = new HmacTokenIssuer(secret, config.auth.tokenTtlMinutes * 60L);
        if (config.xsuaa.present)
            xsuaa = new XsuaaTokenValidator(config.xsuaa.xsappname, config.xsuaa.verificationKey);
        extractor = new CompositeTextExtractor(config.search.pdftotext, config.search.extractTimeoutSeconds);
        metrics = new RequestMetrics;
        audit = new AuditLog(memory ? "" : buildPath(config.storage.dataDir, "audit"));

        mapper = new DtoMapper(userRepo, spaceRepo, documentRepo);
        resolver = new AccessResolver(spaceRepo, membershipRepo);
        indexer = new SearchIndexer(new SearchEngine);
        extraction = new TextExtractionService(documentRepo, blobs, extractor, indexer);
        extractionWorker = new TextExtractionWorker(extraction, synchronousExtraction);
        events = new EventBus;
        events.subscribe(audit);
        events.subscribe(extractionWorker);

        identity = new TokenIdentityService(tokens, xsuaa, userRepo, clock, ids);
        bootstrap = new BootstrapService(userRepo, spaceRepo, membershipRepo, articleRepo, hasher, clock, ids);
        auth = new AuthInteractor(userRepo, hasher, tokens, clock, events, mapper, resolver);
        users = new UserInteractor(userRepo, spaceRepo, membershipRepo, resolver, hasher, clock, ids, events, mapper);
        spaces = new SpaceInteractor(spaceRepo, membershipRepo, userRepo, articleRepo, documentRepo, resolver, clock,
            ids, events, mapper);
        articles = new ArticleInteractor(articleRepo, versionRepo, spaceRepo, documentRepo, indexer, resolver, clock,
            ids, events, mapper);
        MediaSettings ms;
        ms.maxUploadBytes = config.media.maxUploadMB * 1024UL * 1024UL;
        ms.quotaBytes = config.media.quotaMB * 1024UL * 1024UL;
        foreach (e; config.media.allowedExtensions)
            ms.allowedExtensions ~= e.length && e[0] != '.' ? "." ~ e : e;
        documents = new DocumentInteractor(documentRepo, articleRepo, spaceRepo, blobs, mimeTypes, indexer, resolver,
            clock, ids, events, mapper, ms);
        search = new SearchInteractor(indexer, resolver, articleRepo, documentRepo, mapper, events, clock);
        statistics = new StatisticsInteractor(userRepo, spaceRepo, articleRepo, documentRepo, blobs, indexer, resolver,
            mapper);
    }

    /// Seeds an empty store, builds the search index, queues pending text extractions.
    void start() {
        auto b = config.bootstrap;
        auto r = bootstrap.run(BootstrapSettings(b.adminUser, b.adminPassword, b.demoContent), () => randomSecret(12));
        if (r.migratedManagers || r.migratedMemberships)
            logInfo("migration: %s area(s) got a category manager, %s membership(s) created from global roles",
                r.migratedManagers, r.migratedMemberships);
        if (r.performed) {
            logInfo("bootstrap: created administrator '%s'", b.adminUser);
            if (r.generatedPassword.length)
                logWarn("bootstrap: generated password for '%s': %s (change it after the first login)",
                    b.adminUser, r.generatedPassword);
        }
        indexer.rebuild(articleRepo, documentRepo);
        string[] pending;
        foreach (d; documentRepo.all())
            if (!d.textExtracted && d.text.length == 0)
                pending ~= d.id;
        if (pending.length)
            extractionWorker.enqueue(pending);
    }

    AdminCli cli() {
        return new AdminCli(users, userRepo, search);
    }

    HttpServer httpServer() {
        auto s = config.server;
        HttpOptions o;
        o.port = s.port;
        o.bindAddresses = s.bindAddresses;
        o.frontendDir = s.frontendDir;
        o.corsOrigin = s.corsOrigin;
        o.maxUploadBytes = config.media.maxUploadMB * 1024UL * 1024UL;
        o.logRequests = config.log.requests;
        auto server = new HttpServer(o, metrics);
        auto r = server.routes;
        const maxBody = cast(size_t) s.maxRequestBytes;
        new AuthController(auth, identity, config.auth.mode, maxBody).register(r);
        new UserController(users, identity, maxBody).register(r);
        new SpaceController(spaces, identity, maxBody).register(r);
        new ArticleController(articles, identity, maxBody).register(r);
        new DocumentController(documents, identity, maxBody, cast(size_t) o.maxUploadBytes, metrics).register(r);
        new SearchController(search, statistics, identity, metrics).register(r);
        new AdminController(search, identity, audit, metrics, () => extractionWorker.pending).register(r);
        new ODataService(spaces, articles, documents, identity).register(r);
        return server;
    }
}
