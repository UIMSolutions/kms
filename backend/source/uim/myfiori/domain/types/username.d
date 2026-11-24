/// Validation rules for user names, e-mail addresses, passwords and space keys.
module uim.myfiori.domain.types.username;

import std.algorithm.searching : all, canFind, count;
import std.ascii : isAlphaNum, isUpper, isLower, isDigit;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.domain.exceptions;

/// 3-40 chars: a-z 0-9 . _ - ; lower-cased.
string validUsername(string raw) {
    auto u = raw.strip.toLower;
    if (u.length < 3 || u.length > 40)
        throw new ValidationException("User name must have 3 to 40 characters");
    if (!u.all!(c => isAlphaNum(c) || c == '.' || c == '_' || c == '-'))
        throw new ValidationException("User name may only contain a-z, 0-9, '.', '_' and '-'");
    return u;
}

/// Simple structural e-mail check (empty is allowed).
string validEmail(string raw) {
    auto e = raw.strip;
    if (e.length == 0)
        return e;
    if (e.length > 254 || e.count('@') != 1 || e[0] == '@' || e[$ - 1] == '@' || !e[e.countUntilAt + 1 .. $].canFind('.'))
        throw new ValidationException("Invalid e-mail address");
    return e;
}

private size_t countUntilAt(string e) {
    foreach (i, c; e)
        if (c == '@')
            return i;
    return e.length;
}

/// Password policy: at least 10 characters with upper, lower case letters and a digit.
void checkPasswordPolicy(string pw) {
    if (pw.length < 10)
        throw new ValidationException("Password must have at least 10 characters");
    if (pw.length > 256)
        throw new ValidationException("Password too long");
    bool up, low, dig;
    foreach (c; pw) {
        up |= isUpper(c);
        low |= isLower(c);
        dig |= isDigit(c);
    }
    if (!(up && low && dig))
        throw new ValidationException("Password must contain upper and lower case letters and a digit");
}

/// Space keys: 2-20 chars A-Z 0-9, upper-cased (e.g. "HR", "DEV").
string validSpaceKey(string raw) {
    import std.uni : toUpper;
    auto k = raw.strip.toUpper;
    if (k.length < 2 || k.length > 20 || !k.all!(c => (c >= 'A' && c <= 'Z') || isDigit(c)))
        throw new ValidationException("Space key must have 2 to 20 characters A-Z / 0-9");
    return k;
}

unittest {
    assert(validUsername(" Anna.Meyer ") == "anna.meyer");
    assert(validEmail("a@b.de") == "a@b.de");
    bool thrown;
    try
        validEmail("a@b");
    catch (ValidationException)
        thrown = true;
    assert(thrown);
    checkPasswordPolicy("Secret12345");
    assert(validSpaceKey("dev1") == "DEV1");
}
