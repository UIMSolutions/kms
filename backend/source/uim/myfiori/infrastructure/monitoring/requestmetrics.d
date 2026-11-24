/// Request counters and latency (exposed via /api/v1/admin/metrics and /metrics).
module uim.myfiori.infrastructure.monitoring.requestmetrics;

import std.array : appender;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.format : format;
import vibe.data.json;

final class RequestMetrics {
    private SysTime started;
    private ulong total;
    private ulong[int] byStatusClass; // 2,3,4,5
    private double totalMillis = 0;
    private double maxMillis = 0;
    private ulong uploads;
    private ulong uploadBytes;
    private ulong searches;

    this() {
        started = Clock.currTime;
    }

    void record(int status, double millis) {
        total++;
        byStatusClass[status / 100]++;
        totalMillis += millis;
        if (millis > maxMillis)
            maxMillis = millis;
    }

    void recordUpload(ulong bytes) {
        uploads++;
        uploadBytes += bytes;
    }

    void recordSearch() {
        searches++;
    }

    Json toJson() {
        auto j = Json.emptyObject;
        j["startedAt"] = started.toUTC.toISOExtString;
        j["uptimeSeconds"] = (Clock.currTime - started).total!"seconds";
        j["requests"] = total;
        auto s = Json.emptyObject;
        foreach (k, v; byStatusClass)
            s[k.to!string ~ "xx"] = v;
        j["byStatus"] = s;
        j["avgMillis"] = total ? totalMillis / total : 0.0;
        j["maxMillis"] = maxMillis;
        j["uploads"] = uploads;
        j["uploadBytes"] = uploadBytes;
        j["searches"] = searches;
        return j;
    }

    /// Prometheus text format.
    string toPrometheus() {
        auto o = appender!string;
        o ~= "# TYPE kms_requests_total counter\n";
        foreach (k, v; byStatusClass)
            o ~= format("kms_requests_total{status=\"%sxx\"} %s\n", k, v);
        o ~= format("# TYPE kms_request_duration_ms_sum counter\nkms_request_duration_ms_sum %s\n", totalMillis);
        o ~= format("# TYPE kms_uploads_total counter\nkms_uploads_total %s\n", uploads);
        o ~= format("# TYPE kms_upload_bytes_total counter\nkms_upload_bytes_total %s\n", uploadBytes);
        o ~= format("# TYPE kms_searches_total counter\nkms_searches_total %s\n", searches);
        o ~= format("# TYPE kms_uptime_seconds gauge\nkms_uptime_seconds %s\n",
            (Clock.currTime - started).total!"seconds");
        return o[];
    }
}
