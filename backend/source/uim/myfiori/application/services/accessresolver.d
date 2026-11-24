/// Builds the SpaceAccess (effective area roles) of a principal from the repositories.
module uim.myfiori.application.services.accessresolver;

import uim.myfiori.domain;
import uim.myfiori.ports.repositories;

final class AccessResolver {
    private SpaceRepository spaces;
    private MembershipRepository memberships;

    this(SpaceRepository spaces, MembershipRepository memberships) {
        this.spaces = spaces;
        this.memberships = memberships;
    }

    SpaceTree tree() {
        return new SpaceTree(spaces.all());
    }

    SpaceAccess resolve(in Principal p) {
        return SpaceAccess.resolve(p, tree(), p.isAdmin ? null : memberships.byUser(p.userId));
    }
}
