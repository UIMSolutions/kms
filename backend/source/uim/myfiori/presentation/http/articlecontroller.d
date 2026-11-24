/// /api/v1/articles: knowledge articles, lifecycle and history.
module uim.myfiori.presentation.http.articlecontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.application.dtos;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class ArticleController {
    private ArticleUseCase articles;
    private IdentityService identity;
    private size_t maxBody;

    this(ArticleUseCase articles, IdentityService identity, size_t maxBody) {
        this.articles = articles;
        this.identity = identity;
        this.maxBody = maxBody;
    }

    static ArticleInput parseInput(Json b) {
        ArticleInput i;
        i.spaceId = optString(b, "spaceId");
        i.title = optString(b, "title");
        i.summary = optString(b, "summary");
        i.body = optString(b, "body");
        i.tags = optStrings(b, "tags");
        i.attachmentIds = optStrings(b, "attachmentIds");
        return i;
    }

    private void withEtag(HTTPServerResponse res, ArticleDto a, int status = 200) {
        import std.conv : to;
        res.headers["ETag"] = `W/"` ~ a.version_.to!string ~ `"`;
        sendJson(res, a, status);
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/articles", authed(identity, (p, req, res) {
                ArticleFilter f;
                f.spaceId = qs(req, "space");
                f.includeSubAreas = qs(req, "deep") == "true";
                f.status = qs(req, "status");
                f.tag = qs(req, "tag");
                f.authorId = qs(req, "author");
                f.text = qs(req, "q");
                f.orderBy = qs(req, "orderBy");
                f.skip = qsNum(req, "skip", 0);
                f.top = qsNum(req, "top", 50, 500);
                f.withBody = qs(req, "body") == "true";
                sendJson(res, articles.list(p, f));
            }));
        r.post(apiBase ~ "/articles", authed(identity, (p, req, res) {
                withEtag(res, articles.create(p, parseInput(readJsonBody(req, maxBody))), 201);
            }));
        r.get(apiBase ~ "/articles/:id", authed(identity, (p, req, res) {
                withEtag(res, articles.get(p, req.params["id"], qs(req, "view") == "true"));
            }));
        r.patch(apiBase ~ "/articles/:id", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                withEtag(res, articles.update(p, req.params["id"], parseInput(b), expectedVersion(req, b)));
            }));
        r.delete_(apiBase ~ "/articles/:id", authed(identity, (p, req, res) {
                articles.remove(p, req.params["id"]);
                sendNoContent(res);
            }));
        r.post(apiBase ~ "/articles/:id/publish", authed(identity, (p, req, res) {
                withEtag(res, articles.publish(p, req.params["id"]));
            }));
        r.post(apiBase ~ "/articles/:id/archive", authed(identity, (p, req, res) {
                withEtag(res, articles.archive(p, req.params["id"]));
            }));
        r.post(apiBase ~ "/articles/:id/reopen", authed(identity, (p, req, res) {
                withEtag(res, articles.reopen(p, req.params["id"]));
            }));
        r.get(apiBase ~ "/articles/:id/versions", authed(identity, (p, req, res) {
                auto list = articles.versions(p, req.params["id"]);
                sendJson(res, Json(["items": serializeToJson(list), "total": Json(list.length)]));
            }));
        r.post(apiBase ~ "/articles/:id/versions/:vid/restore", authed(identity, (p, req, res) {
                withEtag(res, articles.restore(p, req.params["id"], req.params["vid"]));
            }));
    }
}
