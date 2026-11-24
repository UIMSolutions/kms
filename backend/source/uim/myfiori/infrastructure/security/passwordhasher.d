/// PBKDF2-HMAC-SHA256 password hashing ("pbkdf2-sha256$<iter>$<salt>$<hash>").
module uim.myfiori.infrastructure.security.passwordhasher;

import std.array : split;
import std.base64 : Base64;
import std.conv : to, ConvException;
import uim.myfiori.infrastructure.security.openssl;
import uim.myfiori.ports.services : PasswordHasher;

final class Pbkdf2PasswordHasher : PasswordHasher {
    private enum prefix = "pbkdf2-sha256";
    private uint iterations;

    this(uint iterations = 210_000) {
        this.iterations = iterations;
    }

    string hash(string password) {
        auto salt = secureRandom(16);
        auto dk = derive(password, salt, iterations);
        return prefix ~ "$" ~ iterations.to!string ~ "$" ~ Base64.encode(salt).idup ~ "$" ~ Base64.encode(dk).idup;
    }

    bool verify(string password, string encoded) {
        auto parts = encoded.split("$");
        if (parts.length != 4 || parts[0] != prefix)
            return false;
        try {
            auto iter = parts[1].to!uint;
            auto salt = Base64.decode(parts[2]);
            auto expected = Base64.decode(parts[3]);
            if (iter == 0 || iter > 10_000_000)
                return false;
            return constantTimeEquals(derive(password, salt, iter), expected);
        } catch (Exception)
            return false;
    }

    private static ubyte[] derive(string password, const(ubyte)[] salt, uint iter) {
        auto dk = new ubyte[32];
        if (PKCS5_PBKDF2_HMAC(password.ptr, cast(int) password.length, salt.ptr, cast(int) salt.length,
                cast(int) iter, EVP_sha256(), cast(int) dk.length, dk.ptr) != 1)
            throw new Exception("PBKDF2 failed");
        return dk;
    }
}

unittest {
    auto h = new Pbkdf2PasswordHasher(1000);
    auto e = h.hash("correct horse");
    assert(h.verify("correct horse", e));
    assert(!h.verify("wrong", e));
    assert(!h.verify("x", "garbage"));
}
