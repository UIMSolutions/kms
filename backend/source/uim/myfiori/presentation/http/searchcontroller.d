/// /api/v1/search: full-text search, suggestions; /api/v1/stats: dashboard figures.
module uim.myfiori.presentation.http.searchcontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.domain.types.searchquery;
import uim.myfiori.infrastructure.monitoring : RequestMetrics;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class SearchController {
    private SearchUseCase search;
    private StatisticsUseCase statistics;
    private IdentityService identity;
    private RequestMetrics metrics;

    this(SearchUseCase search, StatisticsUseCase statistics, IdentityService identity, RequestMetrics metrics) {
        this.search = search;
        this.statistics = statistics;
        this.identity = identity;
        this.metrics = metrics;
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/search", authed(identity, (p, req, res) {
                SearchQuery q;
                q.text = qs(req, "q");
                q.kind = qs(req, "kind");
                q.spaceId = qs(req, "space");
                q.tag = qs(req, "tag");
                q.mediaKind = qs(req, "media");
                q.skip = qsNum(req, "skip", 0);
                q.top = qsNum(req, "top", 20, 200);
                if (metrics !is null)
                    metrics.recordSearch();
                sendJson(res, search.search(p, q));
            }));
        r.get(apiBase ~ "/search/suggest", authed(identity, (p, req, res) {
                sendJson(res, Json(["items": serializeToJson(search.suggest(p, qs(req, "q")))]));
            }));
        r.get(apiBase ~ "/stats", authed(identity, (p, req, res) {
                sendJson(res, statistics.stats(p));
            }));
    }
}
