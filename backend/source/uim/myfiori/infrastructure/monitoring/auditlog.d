/// Audit trail: domain events as JSON lines in `<dataDir>/audit/audit-YYYY-MM.jsonl`,
/// plus an in-memory ring buffer of the latest entries for the admin UI.
module uim.myfiori.infrastructure.monitoring.auditlog;

import std.file : exists, mkdirRecurse, append;
import std.format : format;
import std.path : buildPath;
import vibe.core.log;
import vibe.data.json;
import uim.myfiori.ports.messaging;

final class AuditLog : EventHandler {
    private string dir;    // "" = memory only
    private Json[] recent;
    private enum keep = 500;

    this(string dir) {
        this.dir = dir;
        if (dir.length && !dir.exists)
            mkdirRecurse(dir);
    }

    void handle(in DomainEvent e) {
        if (e.type == "search.query")
            return; // queries are not audited (privacy), only counted
        auto j = Json.emptyObject;
        j["at"] = e.at.toUTC.toISOExtString;
        j["type"] = e.type;
        j["subject"] = e.subjectId;
        j["actor"] = e.actorId;
        j["detail"] = e.detail;
        recent ~= j;
        if (recent.length > keep)
            recent = recent[$ - keep .. $];
        if (dir.length) {
            auto u = e.at.toUTC;
            auto file = buildPath(dir, format("audit-%04d-%02d.jsonl", u.year, cast(int) u.month));
            try
                append(file, j.toString ~ "\n");
            catch (Exception ex)
                logWarn("audit: cannot write %s: %s", file, ex.msg);
        }
    }

    /// Newest first.
    Json[] latest(size_t n, string type = "") {
        Json[] r;
        foreach_reverse (j; recent) {
            if (type.length && j["type"].get!string != type)
                continue;
            r ~= j;
            if (r.length >= n)
                break;
        }
        return r;
    }
}
