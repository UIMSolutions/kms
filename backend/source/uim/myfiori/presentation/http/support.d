/// Shared HTTP plumbing: error mapping, JSON in/out, bearer authentication, CORS, query params.
module uim.myfiori.presentation.http.support;

import std.algorithm.searching : startsWith;
import std.conv : to;
import std.string : strip;
import std.typecons : Nullable, nullable;
import vibe.core.log;
import vibe.data.json;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;
import uim.core : isEmpty;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types.principal;
import uim.myfiori.ports.services : IdentityService;

enum apiBase = "/api/v1";

/// Maps business exceptions to HTTP status codes.
int statusOf(Throwable e) {
    if (cast(UnauthorizedException) e)
        return 401;
    if (cast(ForbiddenException) e)
        return 403;
    if (cast(NotFoundException) e)
        return 404;
    if (cast(ConflictException) e)
        return 409;
    if (cast(PayloadTooLargeException) e)
        return 413;
    if (cast(LockedException) e)
        return 423;
    if (cast(ValidationException) e)
        return 400;
    if (auto h = cast(HTTPStatusException) e)
        return h.status;
    return 500;
}

/// Error payload {"error":{"code","message"}} (OData style, understood by UI5).
void sendError(HTTPServerResponse res, Throwable e) {
    auto status = statusOf(e);
    string message = status == 500 ? "Internal server error" : e.msg;
    if (status == 500)
        logError("unhandled: %s", e.toString);
    if (res.headerWritten)
        return;
    if (status == 401)
        res.headers["WWW-Authenticate"] = `Bearer realm="kms"`;
    auto body = Json(["error": Json(["code": Json(status.to!string), "message": Json(message)])]);
    res.writeBody(body.toString, status, "application/json; charset=utf-8");
}

void sendJson(T)(HTTPServerResponse res, T value, int status = 200) {
    static if (is(T == Json))
        auto j = value;
    else
        auto j = serializeToJson(value);
    res.headers["Cache-Control"] = "no-store";
    res.writeBody(j.toString, status, "application/json; charset=utf-8");
}

void sendNoContent(HTTPServerResponse res) {
    res.statusCode = 204;
    res.writeVoidBody();
}

Json readJsonBody(HTTPServerRequest req, size_t maxBytes) {
    auto text = req.bodyReader.readAllUTF8(false, maxBytes);
    if (text.strip.length == 0)
        return Json.emptyObject;
    try {
        auto j = parseJsonString(text);
        if (j.type != Json.Type.object)
            throw new ValidationException("JSON object expected");
        return j;
    } catch (JSONException e)
        throw new ValidationException("Malformed JSON: " ~ e.msg);
}

// ---- typed access to optional JSON fields (for partial updates)

Nullable!string optString(Json j, string key) {
    auto v = j[key];
    if (v.type == Json.Type.undefined)
        return Nullable!string.init;
    if (v.type == Json.Type.null_)
        return nullable("");
    if (v.type != Json.Type.string)
        throw new ValidationException("'" ~ key ~ "' must be a string");
    return nullable(v.get!string);
}

Nullable!bool optBool(Json j, string key) {
    auto v = j[key];
    if (v.type == Json.Type.undefined || v.type == Json.Type.null_)
        return Nullable!bool.init;
    if (v.type != Json.Type.bool_)
        throw new ValidationException("'" ~ key ~ "' must be a boolean");
    return nullable(v.get!bool);
}

Nullable!(string[]) optStrings(Json j, string key) {
    auto v = j[key];
    if (v.type == Json.Type.undefined)
        return Nullable!(string[]).init;
    string[] r;
    if (v.type == Json.Type.null_)
        return nullable(r);
    if (v.type != Json.Type.array)
        throw new ValidationException("'" ~ key ~ "' must be an array of strings");
    foreach (e; v) {
        if (e.type != Json.Type.string)
            throw new ValidationException("'" ~ key ~ "' must be an array of strings");
        r ~= e.get!string;
    }
    return nullable(r);
}

string requireString(Json j, string key) {
    auto v = optString(j, key);
    return v.isNull ? "" : v.get;
}

// ---- query parameters

string qs(HTTPServerRequest req, string key, string def = "") {
    return req.query.get(key, def);
}

size_t qsNum(HTTPServerRequest req, string key, size_t def, size_t maxValue = size_t.max) {
    auto v = req.query.get(key, "");
    if (v.isEmpty)
        return def;
    try {
        auto n = v.to!size_t;
        return n > maxValue ? maxValue : n;
    } catch (Exception)
        throw new ValidationException("Query parameter '" ~ key ~ "' must be a number");
}

// ---- authentication

string bearerToken(HTTPServerRequest req) {
    auto h = req.headers.get("Authorization", "");
    if (h.length > 7 && (h.startsWith("Bearer ") || h.startsWith("bearer ")))
        return h[7 .. $].strip;
    return "";
}

Principal authenticate(IdentityService identity, HTTPServerRequest req) {
    return identity.authenticate(bearerToken(req));
}

/// Wraps a handler: authenticates, maps exceptions to error responses.
HTTPServerRequestDelegate authed(IdentityService identity,
    void delegate(Principal, HTTPServerRequest, HTTPServerResponse) handler) {
    return (HTTPServerRequest req, HTTPServerResponse res) @trusted {
        try {
            auto p = authenticate(identity, req);
            handler(p, req, res);
        } catch (Exception e)
            sendError(res, e);
    };
}

/// Wraps an anonymous handler with exception mapping.
HTTPServerRequestDelegate open(void delegate(HTTPServerRequest, HTTPServerResponse) handler) {
    return (HTTPServerRequest req, HTTPServerResponse res) @trusted {
        try
            handler(req, res);
        catch (Exception e)
            sendError(res, e);
    };
}

/// Optimistic locking: version from If-Match (W/"3", "3" or 3) or from the body.
long expectedVersion(HTTPServerRequest req, Json body) {
    import std.string : replace;
    auto h = req.headers.get("If-Match", "").replace("W/", "").replace(`"`, "").strip;
    if (h.length && h != "*") {
        try
            return h.to!long;
        catch (Exception)
            throw new ValidationException("Invalid If-Match header");
    }
    auto v = body["version"];
    if (v.type == Json.Type.int_)
        return v.get!long;
    return 0;
}

void applySecurityHeaders(HTTPServerResponse res) {
    res.headers["X-Content-Type-Options"] = "nosniff";
    res.headers["Referrer-Policy"] = "same-origin";
    res.headers["X-Frame-Options"] = "SAMEORIGIN";
}

void applyCors(HTTPServerRequest req, HTTPServerResponse res, string allowedOrigin) {
    if (allowedOrigin.length == 0)
        return;
    auto origin = req.headers.get("Origin", "");
    if (allowedOrigin == "*" || origin == allowedOrigin) {
        res.headers["Access-Control-Allow-Origin"] = allowedOrigin == "*" ? "*" : origin;
        res.headers["Vary"] = "Origin";
        res.headers["Access-Control-Allow-Headers"] =
            "Authorization, Content-Type, If-Match, X-File-Name, X-Title, X-Space, X-Tags, X-Description, Accept";
        res.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS";
        res.headers["Access-Control-Expose-Headers"] = "ETag, Content-Disposition, Location";
        res.headers["Access-Control-Max-Age"] = "600";
    }
}
