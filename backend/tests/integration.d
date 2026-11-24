/// End-to-end tests of the use cases wired through the composition root
/// (memory storage, synchronous text extraction).
module integration;

import std.algorithm : canFind, map;
import std.array : array;
import std.exception : assertThrown;
import uim.myfiori.application;
import uim.myfiori.composition;
import uim.myfiori.domain;
import uim.myfiori.infrastructure.configuration;

private Container newApp() {
    AppConfig c;
    c.storage.driver = "memory";
    c.bootstrap.adminPassword = "Admin-Passw0rd";
    c.auth.tokenSecret = "0123456789abcdef0123456789abcdef";
    c.search.pdftotext = "";
    auto app = new Container(c, 1000, true);
    app.start();
    return app;
}

unittest {
    auto app = newApp();
    // login and identity
    auto login = app.auth.login("admin", "Admin-Passw0rd");
    auto admin = app.identity.authenticate(login.token);
    assert(admin.isAdmin && login.user.role == "admin");
    assertThrown!UnauthorizedException(app.auth.login("admin", "wrong"));

    // user management
    UserInput ui;
    ui.username = "Erika";
    ui.role = "editor";
    ui.password = "Editor-Passw0rd";
    auto erika = app.users.create(admin, ui);
    assert(erika.username == "erika" && erika.mustChangePassword);
    ui.username = "rudi";
    ui.role = "reader";
    ui.password = "Reader-Passw0rd";
    app.users.create(admin, ui);
    auto editor = app.identity.authenticate(app.auth.login("erika", "Editor-Passw0rd").token);
    auto reader = app.identity.authenticate(app.auth.login("rudi", "Reader-Passw0rd").token);
    assertThrown!ForbiddenException(app.users.list(editor, PageRequest.init));
    assertThrown!ConflictException(app.users.create(admin, ui));
    // the last admin cannot be removed / demoted
    UserInput demote;
    demote.role = "reader";
    assertThrown!ConflictException(app.users.update(admin, admin.userId, demote));
    assertThrown!ValidationException(app.users.remove(admin, admin.userId));

    // spaces (demo content exists)
    auto spaces = app.spaces.list(reader);
    assert(spaces.length == 2);
    SpaceInput si;
    si.key = "hr";
    si.name = "Human Resources";
    auto hr = app.spaces.create(admin, si);
    assert(hr.key == "HR");
    assertThrown!ForbiddenException(app.spaces.create(editor, si));

    // articles: draft invisible to readers, published visible and searchable
    ArticleInput ai;
    ai.spaceId = hr.id;
    ai.title = "Vacation policy";
    ai.summary = "How many days of leave you get";
    ai.body = "Every employee receives 30 days of paid vacation per year.";
    ai.tags = ["Leave", "policy"];
    auto art = app.articles.create(editor, ai);
    assert(art.status == "draft" && art.tags == ["leave", "policy"]);
    assertThrown!NotFoundException(app.articles.get(reader, art.id));
    assert(app.search.search(reader, SearchQuery("vacation")).total == 0);
    assert(app.search.search(editor, SearchQuery("vacation")).total == 1);
    app.articles.publish(editor, art.id);
    auto found = app.search.search(reader, SearchQuery("vacation"));
    assert(found.total == 1 && found.hits[0].spaceName == "Human Resources");
    assert(found.hits[0].snippet.canFind("<strong>vacation</strong>"));

    // optimistic locking and history
    ArticleInput upd;
    upd.body = "Every employee receives 32 days of paid vacation per year.";
    assertThrown!ConflictException(app.articles.update(editor, art.id, upd, 1));
    auto updated = app.articles.update(editor, art.id, upd, 2);
    assert(updated.version_ == 3);
    auto history = app.articles.versions(editor, art.id);
    assert(history.length == 2 && history[0].version_ == 2);
    auto restored = app.articles.restore(editor, art.id, history[0].id);
    assert(restored.body.canFind("30 days"));

    // documents: upload, text extraction, full-text search on file content
    UploadInput up;
    up.fileName = "../secret/handbook.md";
    up.mimeType = "";
    up.spaceId = hr.id;
    up.tags = ["handbook"];
    auto doc = app.documents.upload(editor, up, cast(const(ubyte)[]) "# Handbook\nOur onboarding checklist for new colleagues.");
    assert(doc.fileName == "handbook.md" && doc.kind == "document" && doc.mimeType == "text/markdown");
    auto hits = app.search.search(reader, SearchQuery("checklist"));
    assert(hits.total == 1 && hits.hits[0].kind == "document");
    auto content = app.documents.content(reader, doc.id);
    assert(cast(string) content.data == "# Handbook\nOur onboarding checklist for new colleagues.");
    assertThrown!ForbiddenException(app.documents.upload(reader, up, cast(const(ubyte)[]) "x"));
    up.fileName = "evil.exe";
    assertThrown!ValidationException(app.documents.upload(editor, up, cast(const(ubyte)[]) "MZ"));

    // attachments, facets, deletion
    ArticleInput att;
    att.attachmentIds = [doc.id];
    auto withAtt = app.articles.update(editor, art.id, att);
    assert(withAtt.attachments.length == 1);
    SearchQuery fq;
    fq.spaceId = hr.id;
    auto facets = app.search.search(reader, fq);
    assert(facets.total == 2 && facets.kinds.length == 2);
    assertThrown!ConflictException(app.spaces.remove(admin, hr.id));
    app.documents.remove(editor, doc.id);
    assert(app.articles.get(reader, art.id).attachments.length == 0);
    assert(app.search.search(reader, SearchQuery("checklist")).total == 0);

    // statistics and reindex
    auto stats = app.statistics.stats(admin);
    assert(stats.users == 3 && stats.spaces == 3 && stats.publishedArticles == 4);
    assert(app.search.reindex(admin) == 4);
    assert(app.search.suggest(reader, "vac").canFind("vacation"));

    // password change and lockout
    app.auth.changePassword(reader, "Reader-Passw0rd", "Reader-Passw0rd2");
    foreach (i; 0 .. 5)
        assertThrown!UnauthorizedException(app.auth.login("rudi", "nope"));
    assertThrown!LockedException(app.auth.login("rudi", "Reader-Passw0rd2"));
    app.users.unlock(admin, reader.userId);
    assert(app.auth.login("rudi", "Reader-Passw0rd2").token.length);
}
