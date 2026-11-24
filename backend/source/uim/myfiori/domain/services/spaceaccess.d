/// Effective rights of one principal in every area.
///
/// Rules:
///  - system administrators are managers of every area
///  - the category manager of an area is manager of that area and of all its sub-areas
///  - otherwise the user's membership in exactly that area counts (reader / editor);
///    memberships are not inherited, so sub-areas have their own users
///
/// | action                                   | reader | editor | manager | admin |
/// |------------------------------------------|--------|--------|---------|-------|
/// | read published articles, documents       |   x    |   x    |    x    |   x   |
/// | see drafts / archived, write content     |        |   x    |    x    |   x   |
/// | delete own content                       |        |   x    |    x    |   x   |
/// | delete any content of the area           |        |        |    x    |   x   |
/// | edit area, manage members, add sub-area  |        |        |    x    |   x   |
/// | name the manager of a sub-area           |        |        | parent  |   x   |
/// | create / delete top-level areas          |        |        |         |   x   |
module uim.myfiori.domain.services.spaceaccess;

import uim.myfiori.domain.entities;
import uim.myfiori.domain.enumerations;
import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.services.spacetree;
import uim.myfiori.domain.types.principal;

struct SpaceAccess {
    Principal principal;
    SpaceTree tree;
    private SpaceRole[string] roles;     // effective role per area
    private bool[string] viaAncestor;    // manager because of a parent area

    /// `memberships` must be the memberships of `p` (others are ignored).
    static SpaceAccess resolve(in Principal p, SpaceTree tree, Membership[] memberships) {
        SpaceAccess a;
        a.principal = p;
        a.tree = tree;
        SpaceRole[string] member;
        foreach (m; memberships)
            if (m.userId == p.userId && m.role > member.get(m.spaceId, SpaceRole.none))
                member[m.spaceId] = m.role;
        foreach (s; tree.all()) {
            if (p.isAdmin) {
                a.roles[s.id] = SpaceRole.manager;
                continue;
            }
            if (s.managerId.length && s.managerId == p.userId) {
                a.roles[s.id] = SpaceRole.manager;
                continue;
            }
            bool inherited = false;
            foreach (anc; tree.ancestors(s.id))
                if (anc.managerId.length && anc.managerId == p.userId) {
                    inherited = true;
                    break;
                }
            if (inherited) {
                a.roles[s.id] = SpaceRole.manager;
                a.viaAncestor[s.id] = true;
                continue;
            }
            if (auto r = s.id in member)
                a.roles[s.id] = *r;
        }
        return a;
    }

    SpaceRole roleIn(string spaceId) const {
        if (spaceId.length == 0) // content without area (legacy): administrators only
            return principal.isAdmin ? SpaceRole.manager : SpaceRole.none;
        return roles.get(spaceId, SpaceRole.none);
    }

    bool isInheritedManager(string spaceId) const {
        return (spaceId in viaAncestor) !is null;
    }

    bool canRead(string spaceId) const {
        return roleIn(spaceId) >= SpaceRole.reader;
    }

    bool canWrite(string spaceId) const {
        return roleIn(spaceId) >= SpaceRole.editor;
    }

    bool canManage(string spaceId) const {
        return roleIn(spaceId) == SpaceRole.manager;
    }

    bool canReadStatus(string spaceId, string status) const {
        return canRead(spaceId) && (status == "published" || canWrite(spaceId));
    }

    bool canReadArticle(in Article a) const {
        return canRead(a.spaceId) && (a.status == ArticleStatus.published || canWrite(a.spaceId));
    }

    bool canDelete(string spaceId, string ownerId) const {
        return canManage(spaceId) || (canWrite(spaceId) && ownerId == principal.userId);
    }

    /// Top-level areas: administrators. Sub-areas: managers of the parent.
    bool canCreateIn(string parentId) const {
        return parentId.length == 0 ? principal.isAdmin : canManage(parentId);
    }

    /// Who may (re)assign the category manager or delete the area.
    bool canGovern(in Space s) const {
        return principal.isAdmin || (s.parentId.length && canManage(s.parentId));
    }

    /// Areas the principal can see at all.
    string[] readableSpaceIds() const {
        string[] r;
        foreach (id, role; roles)
            if (role >= SpaceRole.reader)
                r ~= id;
        return r;
    }

    bool anyWritable() const {
        foreach (_, role; roles)
            if (role >= SpaceRole.editor)
                return true;
        return false;
    }

    bool anyManaged() const {
        foreach (_, role; roles)
            if (role == SpaceRole.manager)
                return true;
        return false;
    }

    // ---- guards

    void requireRead(string spaceId) const {
        if (!canRead(spaceId))
            throw new NotFoundException("Area not found");
    }

    void requireWrite(string spaceId) const {
        if (!canWrite(spaceId))
            throw new ForbiddenException("Editor role in this area required");
    }

    void requireManage(string spaceId) const {
        if (!canManage(spaceId))
            throw new ForbiddenException("Only the category manager of this area (or an administrator) may do this");
    }

    void requireDelete(string spaceId, string ownerId) const {
        if (!canDelete(spaceId, ownerId))
            throw new ForbiddenException("Only the owner, the category manager or an administrator may delete this item");
    }
}

unittest {
    Space mk(string id, string parent, string manager) {
        auto s = new Space;
        s.id = id;
        s.parentId = parent;
        s.managerId = manager;
        s.name = id;
        return s;
    }

    Membership mem(string space, string user, SpaceRole role) {
        auto m = new Membership;
        m.spaceId = space;
        m.userId = user;
        m.role = role;
        return m;
    }

    auto tree = new SpaceTree([mk("it", "", "mia"), mk("net", "it", "nils"), mk("hr", "", "hanna")]);
    // category manager of IT manages the sub-area too
    auto mia = SpaceAccess.resolve(Principal("mia", "mia", "Mia", Role.user), tree, []);
    assert(mia.canManage("it") && mia.canManage("net") && mia.isInheritedManager("net"));
    assert(!mia.canRead("hr") && mia.canGovern(tree.get("net")) && !mia.canGovern(tree.get("it")));
    // manager of the sub-area does not see the parent
    auto nils = SpaceAccess.resolve(Principal("nils", "nils", "Nils", Role.user), tree, []);
    assert(nils.canManage("net") && !nils.canRead("it") && nils.canCreateIn("net") && !nils.canCreateIn(""));
    // memberships are per area and not inherited
    auto eva = SpaceAccess.resolve(Principal("eva", "eva", "Eva", Role.user), tree,
        [mem("it", "eva", SpaceRole.reader), mem("hr", "eva", SpaceRole.editor)]);
    assert(eva.canRead("it") && !eva.canWrite("it") && !eva.canRead("net") && eva.canWrite("hr"));
    assert(eva.canDelete("hr", "eva") && !eva.canDelete("hr", "other") && eva.anyWritable && !eva.anyManaged);
    // administrators manage everything
    auto adm = SpaceAccess.resolve(Principal("a", "a", "A", Role.admin), tree, []);
    assert(adm.canManage("net") && adm.canCreateIn("") && adm.canRead(""));
    assert(!eva.canRead(""));
}
