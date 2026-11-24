/// /api/v1/auth: login, current user, profile, password.
module uim.myfiori.presentation.http.authcontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.application.dtos;
import uim.myfiori.domain.types.principal;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class AuthController {
    private AuthUseCase auth;
    private IdentityService identity;
    private string mode;
    private size_t maxBody;

    this(AuthUseCase auth, IdentityService identity, string mode, size_t maxBody) {
        this.auth = auth;
        this.identity = identity;
        this.mode = mode;
        this.maxBody = maxBody;
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/auth/config", open((req, res) {
                auto j = Json.emptyObject;
                j["mode"] = mode;
                j["localLogin"] = true;
                j["xsuaa"] = mode == "xsuaa";
                sendJson(res, j);
            }));
        r.post(apiBase ~ "/auth/login", open((req, res) {
                auto b = readJsonBody(req, maxBody);
                sendJson(res, auth.login(requireString(b, "username"), requireString(b, "password")));
            }));
        r.post(apiBase ~ "/auth/logout", open((req, res) {
                // tokens are stateless; the client drops it. Kept for symmetry / approuter.
                sendNoContent(res);
            }));
        r.get(apiBase ~ "/auth/me", authed(identity, (p, req, res) { sendJson(res, auth.me(p)); }));
        r.post(apiBase ~ "/auth/password", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                auth.changePassword(p, requireString(b, "oldPassword"), requireString(b, "newPassword"));
                sendNoContent(res);
            }));
        r.patch(apiBase ~ "/auth/profile", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                ProfileInput input;
                input.displayName = optString(b, "displayName");
                input.email = optString(b, "email");
                sendJson(res, auth.updateProfile(p, input));
            }));
    }
}
