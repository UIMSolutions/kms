/// A person who can sign in.
module uim.myfiori.domain.entities.user;

import std.datetime.systime : SysTime;
import core.time : minutes;
import uim.myfiori.domain.enumerations.role;

enum maxFailedLogins = 5;
enum lockMinutes = 10;

final class User {
    string id;
    string username;      /// unique, lower case
    string displayName;
    string email;
    Role role = Role.reader;
    bool active = true;
    string passwordHash;  /// empty for external (XSUAA) users
    string externalId;    /// XSUAA user_name when provisioned from a token
    bool mustChangePassword;
    uint failedLogins;
    SysTime lockedUntil;
    SysTime lastLoginAt;
    SysTime createdAt;
    SysTime updatedAt;
    long version_ = 1;

    bool isLocked(SysTime now) const {
        return lockedUntil != SysTime.init && lockedUntil > now;
    }

    /// Registers a failed login; locks the account after `maxFailedLogins` attempts.
    void loginFailed(SysTime now) {
        failedLogins++;
        if (failedLogins >= maxFailedLogins) {
            lockedUntil = now + lockMinutes.minutes;
            failedLogins = 0;
        }
    }

    void loginSucceeded(SysTime now) {
        failedLogins = 0;
        lockedUntil = SysTime.init;
        lastLoginAt = now;
    }
}

unittest {
    import std.datetime.systime : Clock;
    auto u = new User;
    auto now = Clock.currTime;
    foreach (i; 0 .. maxFailedLogins)
        u.loginFailed(now);
    assert(u.isLocked(now));
    u.loginSucceeded(now);
    assert(!u.isLocked(now));
}
