/// /api/v1/spaces: areas and sub-areas, category manager, members.
module uim.myfiori.presentation.http.spacecontroller;

import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.application.dtos;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

final class SpaceController {
    private SpaceUseCase spaces;
    private IdentityService identity;
    private size_t maxBody;

    this(SpaceUseCase spaces, IdentityService identity, size_t maxBody) {
        this.spaces = spaces;
        this.identity = identity;
        this.maxBody = maxBody;
    }

    static SpaceInput parseInput(Json b) {
        SpaceInput i;
        i.parentId = optString(b, "parentId");
        i.managerId = optString(b, "managerId");
        i.key = optString(b, "key");
        i.name = optString(b, "name");
        i.description = optString(b, "description");
        i.icon = optString(b, "icon");
        return i;
    }

    void register(URLRouter r) {
        r.get(apiBase ~ "/spaces", authed(identity, (p, req, res) {
                auto list = spaces.list(p);
                sendJson(res, Json(["items": serializeToJson(list), "total": Json(list.length)]));
            }));
        r.post(apiBase ~ "/spaces", authed(identity, (p, req, res) {
                sendJson(res, spaces.create(p, parseInput(readJsonBody(req, maxBody))), 201);
            }));
        r.get(apiBase ~ "/spaces/:id", authed(identity, (p, req, res) {
                sendJson(res, spaces.get(p, req.params["id"]));
            }));
        r.patch(apiBase ~ "/spaces/:id", authed(identity, (p, req, res) {
                sendJson(res, spaces.update(p, req.params["id"], parseInput(readJsonBody(req, maxBody))));
            }));
        r.delete_(apiBase ~ "/spaces/:id", authed(identity, (p, req, res) {
                spaces.remove(p, req.params["id"]);
                sendNoContent(res);
            }));
        r.put(apiBase ~ "/spaces/:id/manager", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                sendJson(res, spaces.setManager(p, req.params["id"], requireString(b, "userId")));
            }));
        r.get(apiBase ~ "/spaces/:id/members", authed(identity, (p, req, res) {
                auto list = spaces.members(p, req.params["id"]);
                sendJson(res, Json(["items": serializeToJson(list), "total": Json(list.length)]));
            }));
        r.put(apiBase ~ "/spaces/:id/members/:userId", authed(identity, (p, req, res) {
                auto b = readJsonBody(req, maxBody);
                sendJson(res, spaces.setMember(p, req.params["id"], req.params["userId"], requireString(b, "role")));
            }));
        r.delete_(apiBase ~ "/spaces/:id/members/:userId", authed(identity, (p, req, res) {
                spaces.removeMember(p, req.params["id"], req.params["userId"]);
                sendNoContent(res);
            }));
    }
}
