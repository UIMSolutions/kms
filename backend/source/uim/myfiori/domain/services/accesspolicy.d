/// Global (system-level) authorization rules. Content and area rights are evaluated per
/// area by SpaceAccess (domain/services/spaceaccess.d).
module uim.myfiori.domain.services.accesspolicy;

import uim.myfiori.domain.exceptions;
import uim.myfiori.domain.types.principal;

struct AccessPolicy {
static:
    bool canAdminister(in Principal p) {
        return p.isAdmin;
    }

    void requireAdmin(in Principal p) {
        if (!canAdminister(p))
            throw new ForbiddenException("Administrator role required");
    }
}
