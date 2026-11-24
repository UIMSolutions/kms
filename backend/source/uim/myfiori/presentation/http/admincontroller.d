/// /api/v1/admin: reindex, audit trail, metrics; plus /healthz and /metrics.
module uim.myfiori.presentation.http.admincontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.domain.services.accesspolicy;
import uim.myfiori.infrastructure.monitoring;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class AdminController {
    private SearchUseCase search;
    private IdentityService identity;
    private AuditLog audit;
    private RequestMetrics metrics;
    private size_t delegate() pendingExtractions;

    this(SearchUseCase search, IdentityService identity, AuditLog audit, RequestMetrics metrics,
        size_t delegate() pendingExtractions) {
        this.search = search;
        this.identity = identity;
        this.audit = audit;
        this.metrics = metrics;
        this.pendingExtractions = pendingExtractions;
    }

    void register(URLRouter r) {
        r.get("/healthz", open((req, res) {
                sendJson(res, Json(["status": Json("UP")]));
            }));
        r.get("/metrics", open((req, res) {
                res.writeBody(metrics.toPrometheus, "text/plain; version=0.0.4");
            }));
        r.post(apiBase ~ "/admin/reindex", authed(identity, (p, req, res) {
                auto n = search.reindex(p);
                sendJson(res, Json(["indexed": Json(n)]));
            }));
        r.get(apiBase ~ "/admin/audit", authed(identity, (p, req, res) {
                AccessPolicy.requireAdmin(p);
                auto items = audit.latest(qsNum(req, "top", 100, 500), qs(req, "type"));
                sendJson(res, Json(["items": Json(items), "total": Json(items.length)]));
            }));
        r.get(apiBase ~ "/admin/metrics", authed(identity, (p, req, res) {
                AccessPolicy.requireAdmin(p);
                auto j = metrics.toJson;
                j["pendingTextExtractions"] = pendingExtractions is null ? 0 : pendingExtractions();
                sendJson(res, j);
            }));
    }
}
