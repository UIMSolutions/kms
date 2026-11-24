/// Validates XSUAA-issued RS256 JWTs (forwarded by the approuter or sent by the SaaS registry)
/// against the verification key from the bound xsuaa service.
module uim.myfiori.infrastructure.security.xsuaavalidator;

import std.algorithm.searching : canFind, startsWith;
import std.array : appender, replace;
import std.datetime.systime : Clock;
import std.string : indexOf, strip;
import std.typecons : Nullable, nullable;
import vibe.data.json;
import uim.myfiori.infrastructure.security.jwt;
import uim.myfiori.infrastructure.security.openssl;
import uim.myfiori.ports.services : ExternalIdentity, ExternalTokenValidator;

final class XsuaaTokenValidator : ExternalTokenValidator {
    private string xsappname;
    private string pem;
    private long leewaySeconds;

    this(string xsappname, string verificationKey, long leewaySeconds = 60) {
        this.xsappname = xsappname;
        this.pem = normalizePem(verificationKey);
        this.leewaySeconds = leewaySeconds;
    }

    Nullable!ExternalIdentity validate(string token) {
        JwtParts p;
        if (!parseJwt(token, p) || str(p.header, "alg") != "RS256")
            return Nullable!ExternalIdentity.init;
        if (!verifyRs256(p.signingInput, p.signature))
            return Nullable!ExternalIdentity.init;
        const now = Clock.currTime.toUnixTime;
        if (num(p.payload, "exp") + leewaySeconds < now)
            return Nullable!ExternalIdentity.init;

        ExternalIdentity id;
        auto prefix = xsappname ~ ".";
        bool forUs = false;
        auto scopes = p.payload["scope"];
        if (scopes.type == Json.Type.array)
            foreach (s; scopes)
                if (s.type == Json.Type.string && s.get!string.startsWith(prefix)) {
                    id.scopes ~= s.get!string[prefix.length .. $];
                    forUs = true;
                }
        auto aud = p.payload["aud"];
        if (aud.type == Json.Type.array)
            foreach (a; aud)
                if (a.type == Json.Type.string && a.get!string == xsappname)
                    forUs = true;
        if (!forUs)
            return Nullable!ExternalIdentity.init;

        id.userName = str(p.payload, "user_name");
        id.email = str(p.payload, "email");
        id.givenName = str(p.payload, "given_name");
        id.familyName = str(p.payload, "family_name");
        return nullable(id);
    }

    private bool verifyRs256(string input, const(ubyte)[] sig) {
        auto bio = BIO_new_mem_buf(pem.ptr, cast(int) pem.length);
        if (bio is null)
            return false;
        scope (exit)
            BIO_free(bio);
        auto key = PEM_read_bio_PUBKEY(bio, null, null, null);
        if (key is null)
            return false;
        scope (exit)
            EVP_PKEY_free(key);
        auto ctx = EVP_MD_CTX_new();
        if (ctx is null)
            return false;
        scope (exit)
            EVP_MD_CTX_free(ctx);
        if (EVP_DigestVerifyInit(ctx, null, EVP_sha256(), null, key) != 1)
            return false;
        return EVP_DigestVerify(ctx, sig.ptr, sig.length, cast(const(ubyte)*) input.ptr, input.length) == 1;
    }

    /// XSUAA sometimes delivers the key on one line; OpenSSL needs 64-char lines.
    static string normalizePem(string key) {
        enum begin = "-----BEGIN PUBLIC KEY-----", end = "-----END PUBLIC KEY-----";
        auto k = key.replace("\\n", "\n").strip;
        auto b = k.indexOf(begin), e = k.indexOf(end);
        if (b < 0 || e < 0)
            return k;
        auto bodyText = k[b + begin.length .. e].replace("\n", "").replace("\r", "").replace(" ", "");
        auto o = appender!string;
        o ~= begin ~ "\n";
        for (size_t i = 0; i < bodyText.length; i += 64) {
            o ~= bodyText[i .. (i + 64 < bodyText.length ? i + 64 : bodyText.length)];
            o ~= "\n";
        }
        o ~= end ~ "\n";
        return o[];
    }
}
