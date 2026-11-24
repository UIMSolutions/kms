/// Driven ports for technical services the application relies on
/// (implemented in infrastructure/*).
module uim.myfiori.ports.services;

import std.datetime.systime : SysTime;
import std.typecons : Nullable;
import uim.myfiori.domain.types.principal;

interface Clock {
    SysTime now();
}

interface IdGenerator {
    string newId();
}

interface PasswordHasher {
    string hash(string password);
    bool verify(string password, string encoded);
}

struct TokenClaims {
    string userId;
    string username;
    string role;
    long expiresAt;
}

/// Issues / verifies the backend's own session tokens (local login).
interface TokenIssuer {
    string issue(in TokenClaims claims);
    Nullable!TokenClaims verify(string token);
    long ttlSeconds();
}

/// Identity from an external IdP token (XSUAA via approuter).
struct ExternalIdentity {
    string userName;
    string email;
    string givenName;
    string familyName;
    string[] scopes; /// without the xsappname prefix
}

interface ExternalTokenValidator {
    Nullable!ExternalIdentity validate(string token);
}

/// Resolves a bearer token to the calling principal (throws UnauthorizedException).
interface IdentityService {
    Principal authenticate(string bearerToken);
}

/// Detects MIME types from file names.
interface MimeTypes {
    string ofFile(string fileName);
}
