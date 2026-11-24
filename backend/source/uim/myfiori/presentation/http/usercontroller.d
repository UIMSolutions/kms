/// /api/v1/users: user management (administrators).
module uim.myfiori.presentation.http.usercontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.application.dtos;
import uim.myfiori.domain.types;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class UserController {
    private UserUseCase users;
    private IdentityService identity;
    private size_t maxBody;

    this(UserUseCase users, IdentityService identity, size_t maxBody) {
        this.users = users;
        this.identity = identity;
        this.maxBody = maxBody;
    }

    static UserInput parseInput(Json b) {
        UserInput i;
        i.username = optString(b, "username");
        i.displayName = optString(b, "displayName");
        i.email = optString(b, "email");
        i.role = optString(b, "role");
        i.active = optBool(b, "active");
        i.password = optString(b, "password");
        i.mustChangePassword = optBool(b, "mustChangePassword");
        return i;
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/users", authed(identity, (p, req, res) {
                PageRequest pr;
                pr.filter = qs(req, "q");
                pr.skip = qsNum(req, "skip", 0);
                pr.top = qsNum(req, "top", 200, 1000);
                sendJson(res, users.list(p, pr));
            }));
        // registered before /users/:id so that "directory" is not taken as an id
        r.get(apiBase ~ "/users/directory", authed(identity, (p, req, res) {
                auto list = users.directory(p, qs(req, "q"));
                sendJson(res, Json(["items": serializeToJson(list), "total": Json(list.length)]));
            }));
        r.get(apiBase ~ "/users/:id/assignments", authed(identity, (p, req, res) {
                auto list = users.assignments(p, req.params["id"]);
                sendJson(res, Json(["items": serializeToJson(list), "total": Json(list.length)]));
            }));
        r.post(apiBase ~ "/users", authed(identity, (p, req, res) {
                sendJson(res, users.create(p, parseInput(readJsonBody(req, maxBody))), 201);
            }));
        r.get(apiBase ~ "/users/:id", authed(identity, (p, req, res) {
                sendJson(res, users.get(p, req.params["id"]));
            }));
        r.patch(apiBase ~ "/users/:id", authed(identity, (p, req, res) {
                sendJson(res, users.update(p, req.params["id"], parseInput(readJsonBody(req, maxBody))));
            }));
        r.delete_(apiBase ~ "/users/:id", authed(identity, (p, req, res) {
                users.remove(p, req.params["id"]);
                sendNoContent(res);
            }));
        r.post(apiBase ~ "/users/:id/password", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                users.resetPassword(p, req.params["id"], requireString(b, "password"));
                sendNoContent(res);
            }));
        r.post(apiBase ~ "/users/:id/unlock", authed(identity, (p, req, res) {
                users.unlock(p, req.params["id"]);
                sendNoContent(res);
            }));
    }
}
