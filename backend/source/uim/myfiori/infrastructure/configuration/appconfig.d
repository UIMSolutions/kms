/// Type-safe configuration model. Defaults here < config/default.json < config/default.yaml
/// < config/local.(json|yaml) < KMS_* environment variables < VCAP_SERVICES.
module uim.myfiori.infrastructure.configuration.appconfig;

struct ServerConfig {
    ushort port = 8080;
    string[] bindAddresses = ["0.0.0.0"];
    string frontendDir = "../frontend"; /// served under /app/ (empty = do not serve)
    string corsOrigin;                  /// e.g. "http://localhost:8081" for `ui5 serve`
    ulong maxRequestBytes = 1024 * 1024; /// JSON bodies
}

struct LogConfig {
    string level = "info";
    bool requests = true;
    string file;
}

struct StorageConfig {
    string driver = "file"; /// "file" (durable) or "memory" (tests / demo)
    string dataDir = "data";
}

struct MediaConfig {
    uint maxUploadMB = 100;
    uint quotaMB = 0; /// 0 = unlimited
    string[] allowedExtensions; /// empty = everything except blocked executables
}

struct AuthConfig {
    string mode = "local"; /// "local" (own login) or "xsuaa" (approuter + XSUAA, local login still possible)
    string tokenSecret;    /// HS256 secret (>= 32 chars); generated per start when empty
    uint tokenTtlMinutes = 480;
}

struct BootstrapConfig {
    string adminUser = "admin";
    string adminPassword; /// generated and logged once when empty
    bool demoContent = true;
}

struct SearchConfig {
    string pdftotext = "pdftotext"; /// poppler-utils binary for PDF text extraction ("" = off)
    uint extractTimeoutSeconds = 60;
}

struct XsuaaConfig {
    bool present;
    string xsappname;
    string verificationKey;
}

struct AppConfig {
    ServerConfig server;
    LogConfig log;
    StorageConfig storage;
    MediaConfig media;
    AuthConfig auth;
    BootstrapConfig bootstrap;
    SearchConfig search;
    XsuaaConfig xsuaa;
    string[] sources; /// files / env layers that contributed (diagnostics)
}
