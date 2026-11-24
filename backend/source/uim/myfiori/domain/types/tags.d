/// Tag normalization: lower case, trimmed, no duplicates, limited length and count.
module uim.myfiori.domain.types.tags;

import std.algorithm : canFind, filter, map, sort, uniq;
import std.array : array, split;
import std.string : strip;
import std.uni : toLower;
import uim.myfiori.domain.exceptions;

enum maxTags = 30;
enum maxTagLength = 48;

string[] normalizeTags(const(string)[] raw) {
    string[] result;
    foreach (t; raw) {
        auto n = t.strip.toLower.idup;
        if (n.length == 0)
            continue;
        if (n.length > maxTagLength)
            throw new ValidationException("Tag too long (max 48 characters): " ~ n);
        if (!result.canFind(n))
            result ~= n;
    }
    if (result.length > maxTags)
        throw new ValidationException("Too many tags (max 30)");
    return result;
}

/// "a, b ,c" -> ["a","b","c"]
string[] parseTagList(string csv) {
    return normalizeTags(csv.split(","));
}

unittest {
    assert(normalizeTags([" Foo", "foo", "", "Bar "]) == ["foo", "bar"]);
    assert(parseTagList("x, y,,X") == ["x", "y"]);
}
