/// Issues and verifies locally signed HS256 JWTs (local login).
module uim.myfiori.infrastructure.security.hmactokenissuer;

import std.datetime.systime : Clock;
import std.digest.hmac : hmac;
import std.digest.sha : SHA256;
import std.string : representation;
import std.typecons : Nullable, nullable;
import vibe.data.json;
import uim.myfiori.infrastructure.security.jwt;
import uim.myfiori.infrastructure.security.openssl : constantTimeEquals;
import uim.myfiori.ports.services : TokenClaims, TokenIssuer;

final class HmacTokenIssuer : TokenIssuer {
    private enum issuer = "uim-kms";
    private immutable(ubyte)[] secret;
    private long ttl;

    this(string secret, long ttlSeconds) {
        assert(secret.length >= 32, "token secret too short");
        this.secret = secret.representation;
        this.ttl = ttlSeconds;
    }

    long ttlSeconds() {
        return ttl;
    }

    string issue(in TokenClaims c) {
        auto header = Json(["alg": Json("HS256"), "typ": Json("JWT")]);
        auto payload = Json.emptyObject;
        payload["iss"] = issuer;
        payload["sub"] = c.userId;
        payload["usr"] = c.username;
        payload["rol"] = c.role;
        payload["iat"] = Clock.currTime.toUnixTime;
        payload["exp"] = c.expiresAt;
        auto input = b64url(header.toString.representation) ~ "." ~ b64url(payload.toString.representation);
        return input ~ "." ~ b64url(sign(input));
    }

    Nullable!TokenClaims verify(string token) {
        JwtParts p;
        if (!parseJwt(token, p) || str(p.header, "alg") != "HS256" || str(p.payload, "iss") != issuer)
            return Nullable!TokenClaims.init;
        if (!constantTimeEquals(sign(p.signingInput), p.signature))
            return Nullable!TokenClaims.init;
        auto exp = num(p.payload, "exp");
        if (exp <= Clock.currTime.toUnixTime)
            return Nullable!TokenClaims.init;
        return nullable(TokenClaims(str(p.payload, "sub"), str(p.payload, "usr"), str(p.payload, "rol"), exp));
    }

    private ubyte[] sign(string input) {
        auto mac = input.representation.hmac!SHA256(secret);
        return mac[].dup;
    }
}

unittest {
    auto issuer = new HmacTokenIssuer("0123456789abcdef0123456789abcdef", 60);
    auto t = issuer.issue(TokenClaims("u1", "anna", "editor", Clock.currTime.toUnixTime + 60));
    auto c = issuer.verify(t);
    assert(!c.isNull && c.get.userId == "u1" && c.get.role == "editor");
    assert(issuer.verify(t ~ "x").isNull);
    auto other = new HmacTokenIssuer("ffffffffffffffffffffffffffffffff", 60);
    assert(other.verify(t).isNull);
}
