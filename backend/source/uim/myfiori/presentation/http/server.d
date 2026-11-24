/// HTTP listener: router, static frontend (/app/), request logging, metrics, CORS.
module uim.myfiori.presentation.http.server;

import std.datetime.stopwatch : StopWatch, AutoStart;
import std.file : exists;
import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router : URLRouter;
import vibe.http.server;
import uim.myfiori.infrastructure.monitoring : RequestMetrics;
import uim.myfiori.presentation.http.support;

struct HttpOptions {
    ushort port = 8080;
    string[] bindAddresses = ["0.0.0.0"];
    string frontendDir;
    string corsOrigin;
    ulong maxUploadBytes = 100 * 1024 * 1024;
    bool logRequests = true;
}

final class HttpServer {
    URLRouter routes;
    private HttpOptions options;
    private RequestMetrics metrics;
    private HTTPListener listener;

    this(HttpOptions options, RequestMetrics metrics) {
        this.options = options;
        this.metrics = metrics;
        routes = new URLRouter;
        if (options.frontendDir.length && options.frontendDir.exists) {
            auto fs = new HTTPFileServerSettings("/app");
            fs.cacheControl = "no-cache";
            routes.get("/", (HTTPServerRequest req, HTTPServerResponse res) @safe {
                res.redirect("/app/index.html");
            });
            routes.get("/app", (HTTPServerRequest req, HTTPServerResponse res) @safe {
                res.redirect("/app/index.html");
            });
            routes.get("/app/*", serveStaticFiles(options.frontendDir, fs));
            logInfo("serving frontend from %s at /app/", options.frontendDir);
        }
    }

    /// Delegate for tests (no socket).
    void handle(HTTPServerRequest req, HTTPServerResponse res) @trusted {
        auto sw = StopWatch(AutoStart.yes);
        applySecurityHeaders(res);
        applyCors(req, res, options.corsOrigin);
        if (req.method == HTTPMethod.OPTIONS) {
            res.statusCode = 204;
            res.writeVoidBody();
        } else {
            try
                routes.handleRequest(req, res);
            catch (Exception e)
                sendError(res, e);
            if (!res.headerWritten) {
                res.writeBody(`{"error":{"code":"404","message":"Not found"}}`, 404, "application/json; charset=utf-8");
            }
        }
        auto ms = sw.peek.total!"usecs" / 1000.0;
        metrics.record(res.statusCode, ms);
        if (options.logRequests)
            logInfo("%s %s -> %s (%.1f ms)", req.method, req.requestURI, res.statusCode, ms);
    }

    void listen() {
        auto s = new HTTPServerSettings;
        s.port = options.port;
        s.bindAddresses = options.bindAddresses;
        s.maxRequestSize = options.maxUploadBytes + 1024 * 1024;
        s.serverString = "uim-kms";
        s.options |= HTTPServerOption.reusePort;
        listener = listenHTTP(s, &handle);
        logInfo("listening on %s port %s", options.bindAddresses, options.port);
    }

    void stop() {
        listener.stopListening();
    }
}
