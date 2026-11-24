/// Technical logging: level configuration and optional log file.
module uim.myfiori.infrastructure.logging;

import std.uni : toLower;
import vibe.core.log;

LogLevel parseLevel(string level) {
    switch (level.toLower) {
    case "trace":
        return LogLevel.trace;
    case "debug":
        return LogLevel.debug_;
    case "diagnostic":
        return LogLevel.diagnostic;
    case "warn", "warning":
        return LogLevel.warn;
    case "error":
        return LogLevel.error;
    default:
        return LogLevel.info;
    }
}

/// Sets the console level and, if `file` is given, additionally logs to that file.
void configureLogging(string level, string file = "") {
    auto l = parseLevel(level);
    setLogLevel(l);
    if (file.length)
        setLogFile(file, l);
}
