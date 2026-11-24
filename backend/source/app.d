/// Entry point: loads configuration, builds the object graph, runs a CLI command or the HTTP server.
module app;

import std.process : environment;
import vibe.core.core : runApplication;
import vibe.core.log;
import uim.myfiori.composition;
import uim.myfiori.infrastructure.configuration;
import uim.myfiori.infrastructure.logging : configureLogging;
import uim.myfiori.presentation.cli : AdminCli;
import uim.myfiori.application.services.bootstrapservice : BootstrapSettings;

int main(string[] args) {
    AppConfig config;
    try
        config = loadConfig(environment.get("KMS_CONFIG_DIR", "config"));
    catch (Exception e) {
        logError("configuration error: %s", e.msg);
        return 2;
    }
    configureLogging(config.log.level, config.log.file);

    Container app;
    try
        app = new Container(config);
    catch (Exception e) {
        logError("start-up failed: %s", e.msg);
        return 2;
    }

    if (AdminCli.isCommand(args)) {
        app.bootstrap.run(BootstrapSettings(config.bootstrap.adminUser, config.bootstrap.adminPassword,
                config.bootstrap.demoContent), () => "");
        app.indexer.rebuild(app.articleRepo, app.documentRepo);
        return app.cli.run(args);
    }

    logInfo("uim KMS starting (auth=%s, storage=%s at %s, config=%s)", config.auth.mode, config.storage.driver,
        config.storage.dataDir, config.sources);
    app.start();
    app.extractionWorker.start();
    try
        app.httpServer().listen();
    catch (Exception e) {
        logError("cannot start the HTTP server: %s", e.msg);
        return 2;
    }
    string[] unrecognized; // vibe.d must not parse our CLI flags
    auto rc = runApplication(&unrecognized);
    app.extractionWorker.stop();
    app.storage.flush();
    return rc;
}
