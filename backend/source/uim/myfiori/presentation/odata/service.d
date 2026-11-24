/// Read-only OData v4 service at /odata/v4/kms/ exposing Spaces, Articles and Documents,
/// e.g. for Fiori elements list reports, SAP Analytics or Excel. Supports $top, $skip,
/// $count, $search, $select and single-entity access by key. Writes go through the
/// REST API (/api/v1).
module uim.myfiori.presentation.odata.service;

import std.algorithm : canFind, map, min;
import std.array : array, join, split;
import std.conv : to;
import std.string : strip;
import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.application.dtos;
import uim.myfiori.domain.types;
import uim.myfiori.ports;
import uim.myfiori.presentation.http.support;

enum odataBase = "/odata/v4/kms";

private struct Prop {
    string name;
    string type;
}

private immutable Prop[][string] entityProps;
private immutable string[string] entityTypeOf;

shared static this() {
    entityProps = [
        "Spaces": [
            Prop("id", "Edm.String"), Prop("key", "Edm.String"), Prop("name", "Edm.String"),
            Prop("description", "Edm.String"), Prop("icon", "Edm.String"), Prop("articleCount", "Edm.Int64"),
            Prop("documentCount", "Edm.Int64"), Prop("createdAt", "Edm.String"), Prop("updatedAt", "Edm.String")
        ],
        "Articles": [
            Prop("id", "Edm.String"), Prop("spaceId", "Edm.String"), Prop("spaceName", "Edm.String"),
            Prop("title", "Edm.String"), Prop("summary", "Edm.String"), Prop("status", "Edm.String"),
            Prop("authorName", "Edm.String"), Prop("createdAt", "Edm.String"), Prop("updatedAt", "Edm.String"),
            Prop("publishedAt", "Edm.String"), Prop("views", "Edm.Int64")
        ],
        "Documents": [
            Prop("id", "Edm.String"), Prop("spaceId", "Edm.String"), Prop("spaceName", "Edm.String"),
            Prop("title", "Edm.String"), Prop("description", "Edm.String"), Prop("fileName", "Edm.String"),
            Prop("mimeType", "Edm.String"), Prop("kind", "Edm.String"), Prop("size", "Edm.Int64"),
            Prop("uploadedByName", "Edm.String"), Prop("createdAt", "Edm.String"),
            Prop("updatedAt", "Edm.String"), Prop("downloads", "Edm.Int64"), Prop("contentUrl", "Edm.String")
        ]
    ];
    entityTypeOf = ["Spaces": "Space", "Articles": "Article", "Documents": "Document"];
}

/// CSDL XML for the service.
string metadataXml() {
    auto o = `<?xml version="1.0" encoding="utf-8"?>`
        ~ `<edmx:Edmx xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx" Version="4.0">`
        ~ `<edmx:DataServices><Schema xmlns="http://docs.oasis-open.org/odata/ns/edm" Namespace="KMS">`;
    foreach (set; ["Spaces", "Articles", "Documents"]) {
        o ~= `<EntityType Name="` ~ entityTypeOf[set] ~ `"><Key><PropertyRef Name="id"/></Key>`;
        foreach (p; entityProps[set])
            o ~= `<Property Name="` ~ p.name ~ `" Type="` ~ p.type ~ `"` ~ (p.name == "id" ? ` Nullable="false"` : "") ~ `/>`;
        o ~= `</EntityType>`;
    }
    o ~= `<EntityContainer Name="Container">`;
    foreach (set; ["Spaces", "Articles", "Documents"])
        o ~= `<EntitySet Name="` ~ set ~ `" EntityType="KMS.` ~ entityTypeOf[set] ~ `"/>`;
    o ~= `</EntityContainer></Schema></edmx:DataServices></edmx:Edmx>`;
    return o;
}

final class ODataService {
    private SpaceUseCase spaces;
    private ArticleUseCase articles;
    private DocumentUseCase documents;
    private IdentityService identity;

    this(SpaceUseCase spaces, ArticleUseCase articles, DocumentUseCase documents, IdentityService identity) {
        this.spaces = spaces;
        this.articles = articles;
        this.documents = documents;
        this.identity = identity;
    }

    void register(URLRouter r) {
        r.get(odataBase ~ "/", open((req, res) {
                auto sets = Json.emptyArray;
                foreach (s; ["Spaces", "Articles", "Documents"])
                    sets ~= Json(["name": Json(s), "kind": Json("EntitySet"), "url": Json(s)]);
                odataJson(res, Json(["@odata.context": Json("$metadata"), "value": sets]));
            }));
        r.get(odataBase ~ "/$metadata", open((req, res) {
                res.headers["OData-Version"] = "4.0";
                res.writeBody(metadataXml(), "application/xml");
            }));
        r.get(odataBase ~ "/:set", authed(identity, (p, req, res) {
                import std.string : indexOf;
                auto raw = req.params["set"];
                auto paren = raw.indexOf('(');
                if (paren > 0)
                    return single(p, req, res, raw[0 .. paren], raw[paren + 1 .. $ - 1]);
                collection(p, req, res, raw);
            }));
    }

    private Json[] load(in Principal p, string set, string search) {
        Json[] rows;
        switch (set) {
        case "Spaces":
            foreach (s; spaces.list(p))
                if (search.length == 0 || matches(s.name ~ " " ~ s.description, search))
                    rows ~= serializeToJson(s);
            break;
        case "Articles":
            ArticleFilter f;
            f.text = search;
            f.top = 0;
            foreach (a; articles.list(p, f).items)
                rows ~= serializeToJson(a);
            break;
        case "Documents":
            DocumentFilter f;
            f.text = search;
            f.top = 0;
            foreach (d; documents.list(p, f).items)
                rows ~= serializeToJson(d);
            break;
        default:
            throw new HTTPStatusException(404, "Unknown entity set " ~ set);
        }
        return rows;
    }

    private void collection(in Principal p, HTTPServerRequest req, HTTPServerResponse res, string set) {
        auto rows = load(p, set, qs(req, "$search").strip);
        auto skip = min(qsNum(req, "$skip", 0), rows.length);
        auto top = qsNum(req, "$top", 1000, 5000);
        auto page = rows[skip .. min(skip + top, rows.length)];
        auto select = selectList(req);
        auto value = Json.emptyArray;
        foreach (row; page)
            value ~= shape(set, row, select);
        auto body = Json.emptyObject;
        body["@odata.context"] = "$metadata#" ~ set;
        if (qs(req, "$count") == "true")
            body["@odata.count"] = rows.length;
        body["value"] = value;
        odataJson(res, body);
    }

    private void single(in Principal p, HTTPServerRequest req, HTTPServerResponse res, string set, string key) {
        import std.string : replace;
        auto id = key.strip;
        if (id.length >= 2 && id[0] == '\'' && id[$ - 1] == '\'')
            id = id[1 .. $ - 1].replace("''", "'");
        Json row;
        switch (set) {
        case "Spaces":
            row = serializeToJson(spaces.get(p, id));
            break;
        case "Articles":
            row = serializeToJson(articles.get(p, id));
            break;
        case "Documents":
            row = serializeToJson(documents.get(p, id));
            break;
        default:
            throw new HTTPStatusException(404, "Unknown entity set " ~ set);
        }
        auto j = shape(set, row, selectList(req));
        j["@odata.context"] = "$metadata#" ~ set ~ "/$entity";
        odataJson(res, j);
    }

    private static string[] selectList(HTTPServerRequest req) {
        auto s = qs(req, "$select");
        return s.length ? s.split(",").map!(x => x.strip).array : null;
    }

    /// Projects a DTO onto the declared properties (and $select).
    private static Json shape(string set, Json row, string[] select) {
        auto o = Json.emptyObject;
        foreach (p; entityProps[set]) {
            if (select.length && !select.canFind(p.name) && p.name != "id")
                continue;
            auto v = row[p.name];
            o[p.name] = v.type == Json.Type.undefined ? Json(null) : v;
        }
        return o;
    }

    private static bool matches(string text, string search) {
        import std.uni : toLower;
        return text.toLower.canFind(search.toLower);
    }

    private static void odataJson(HTTPServerResponse res, Json body) {
        res.headers["OData-Version"] = "4.0";
        res.writeBody(body.toString, "application/json;odata.metadata=minimal");
    }
}
