/// Navigation in the area hierarchy: ancestors, descendants, paths, depth, cycle checks.
module uim.myfiori.domain.services.spacetree;

import std.algorithm : canFind, sort;
import std.array : join;
import uim.myfiori.domain.entities.space;
import uim.myfiori.domain.exceptions;

final class SpaceTree {
    private Space[string] byId;
    private string[][string] childIds;

    this(Space[] spaces) {
        foreach (s; spaces)
            byId[s.id] = s;
        foreach (s; spaces)
            if (s.parentId.length && (s.parentId in byId))
                childIds[s.parentId] ~= s.id;
    }

    Space get(string id) {
        if (auto s = id in byId)
            return *s;
        return null;
    }

    Space[] all() {
        return byId.values;
    }

    /// Parent chain, nearest first (cycle-safe).
    Space[] ancestors(string id) {
        Space[] r;
        auto s = get(id);
        bool[string] seen;
        while (s !is null && s.parentId.length && (s.parentId !in seen) && r.length < 64) {
            seen[s.parentId] = true;
            auto p = get(s.parentId);
            if (p is null)
                break;
            r ~= p;
            s = p;
        }
        return r;
    }

    string[] children(string id) {
        return childIds.get(id, null);
    }

    /// All sub-areas below `id` (depth first, without `id`).
    string[] descendants(string id) {
        string[] r;
        void walk(string x, int guard) {
            if (guard > 64)
                return;
            foreach (c; children(x)) {
                r ~= c;
                walk(c, guard + 1);
            }
        }

        walk(id, 0);
        return r;
    }

    /// 1 for a top-level area.
    size_t depth(string id) {
        return get(id) is null ? 0 : ancestors(id).length + 1;
    }

    /// Height of the subtree below `id` (0 = no sub-areas).
    size_t height(string id) {
        size_t h = 0;
        foreach (c; children(id)) {
            auto ch = height(c) + 1;
            if (ch > h)
                h = ch;
        }
        return h;
    }

    /// "IT / Network / VPN"
    string path(string id, string separator = " / ") {
        auto s = get(id);
        if (s is null)
            return "";
        string[] names = [s.name];
        foreach (a; ancestors(id))
            names = a.name ~ names;
        return names.join(separator);
    }

    /// Ensures that `id` can be placed below `newParentId` (exists, no cycle, depth limit).
    void checkParent(string id, string newParentId) {
        if (newParentId.length == 0)
            return;
        auto parent = get(newParentId);
        if (parent is null)
            throw new ValidationException("Parent area not found");
        if (id.length && (newParentId == id || descendants(id).canFind(newParentId)))
            throw new ValidationException("An area cannot be moved below itself or one of its sub-areas");
        const subtree = id.length ? height(id) : 0;
        if (depth(newParentId) + 1 + subtree > maxSpaceDepth)
            throw new ValidationException("Areas can be nested at most 5 levels deep");
    }
}

unittest {
    Space mk(string id, string parent, string name) {
        auto s = new Space;
        s.id = id;
        s.parentId = parent;
        s.name = name;
        return s;
    }

    auto t = new SpaceTree([mk("it", "", "IT"), mk("net", "it", "Network"), mk("vpn", "net", "VPN"), mk("hr", "", "HR")]);
    assert(t.path("vpn") == "IT / Network / VPN");
    assert(t.depth("vpn") == 3 && t.depth("it") == 1);
    assert(t.descendants("it") == ["net", "vpn"]);
    assert(t.height("it") == 2);
    bool thrown;
    try
        t.checkParent("it", "vpn");
    catch (ValidationException)
        thrown = true;
    assert(thrown);
    t.checkParent("hr", "vpn"); // depth 4: fine
}
