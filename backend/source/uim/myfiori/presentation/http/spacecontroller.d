/// /api/v1/spaces: knowledge spaces.
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
    }
}
