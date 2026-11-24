/// JSON Web Token helpers (compact serialization, base64url).
module uim.myfiori.infrastructure.security.jwt;

import std.array : split;
import std.base64 : Base64URLNoPadding;
import std.string : representation, stripRight;
import vibe.data.json;

struct JwtParts {
    Json header;
    Json payload;
    string signingInput;  /// "<header>.<payload>"
    ubyte[] signature;
}

string b64url(const(ubyte)[] data) {
    return Base64URLNoPadding.encode(data).idup;
}

ubyte[] unb64url(string s) {
    // tolerate padded input
    return Base64URLNoPadding.decode(s.stripRight("="));
}

/// Splits and decodes a JWT; returns false if it is malformed.
bool parseJwt(string token, out JwtParts parts) {
    auto segs = token.split(".");
    if (segs.length != 3)
        return false;
    try {
        parts.header = parseJsonString(cast(string) unb64url(segs[0]));
        parts.payload = parseJsonString(cast(string) unb64url(segs[1]));
        parts.signature = unb64url(segs[2]);
        parts.signingInput = segs[0] ~ "." ~ segs[1];
        return parts.header.type == Json.Type.object && parts.payload.type == Json.Type.object;
    } catch (Exception)
        return false;
}

string str(Json o, string key) {
    auto v = o[key];
    return v.type == Json.Type.string ? v.get!string : "";
}

long num(Json o, string key) {
    auto v = o[key];
    if (v.type == Json.Type.int_)
        return v.get!long;
    if (v.type == Json.Type.float_)
        return cast(long) v.get!double;
    return 0;
}
