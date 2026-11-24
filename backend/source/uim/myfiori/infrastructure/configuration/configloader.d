/// Builds the AppConfig: defaults -> config files -> environment -> VCAP_SERVICES.
module uim.myfiori.infrastructure.configuration.configloader;

import std.algorithm.searching : canFind;
import std.array : split;
import std.conv : to;
import std.file : exists, readText;
import std.path : buildPath;
import std.process : environment;
import std.string : strip;
import vibe.data.json;
import uim.myfiori.infrastructure.configuration.appconfig;

/// Loads the configuration from `configDir` and the process environment.
AppConfig loadConfig(string configDir, string[string] env = null) {
    if (env is null)
        env = environment.toAA;
    auto tree = serializeToJson(AppConfig.init);
    string[] sources = ["defaults"];
    foreach (name; ["default.json", "default.yaml", "local.json", "local.yaml"]) {
        auto file = buildPath(configDir, name);
        if (!file.exists)
            continue;
        auto layer = name.canFind(".json") ? parseJsonString(readText(file), file) : yamlToJson(file);
        tree = merge(tree, layer);
        sources ~= file;
    }
    if (applyEnvironment(tree, env))
        sources ~= "env";
    if (auto v = "VCAP_SERVICES" in env)
        if (applyVcap(tree, *v))
            sources ~= "VCAP_SERVICES";
    tree["sources"] = serializeToJson(sources);
    auto cfg = deserializeJson!AppConfig(tree);
    validate(cfg);
    return cfg;
}

private void validate(ref AppConfig c) {
    if (!["file", "memory"].canFind(c.storage.driver))
        throw new Exception("storage.driver must be 'file' or 'memory'");
    if (!["local", "xsuaa"].canFind(c.auth.mode))
        throw new Exception("auth.mode must be 'local' or 'xsuaa'");
    if (c.auth.tokenSecret.length && c.auth.tokenSecret.length < 32)
        throw new Exception("auth.tokenSecret must have at least 32 characters");
    if (c.auth.mode == "xsuaa" && !c.xsuaa.present)
        throw new Exception("auth.mode=xsuaa requires a bound xsuaa service (VCAP_SERVICES)");
    if (c.media.maxUploadMB == 0)
        throw new Exception("media.maxUploadMB must be > 0");
}

/// Deep merge: objects are merged recursively, everything else is replaced.
Json merge(Json base, Json overlay) {
    if (base.type != Json.Type.object || overlay.type != Json.Type.object)
        return overlay;
    auto r = base.clone;
    foreach (string k, v; overlay) {
        auto existing = r[k];
        r[k] = existing.type == Json.Type.object && v.type == Json.Type.object ? merge(existing, v) : v;
    }
    return r;
}

private Json yamlToJson(string file) {
    import dyaml : Loader, Node, NodeType;

    static Json convert(Node n) {
        switch (n.type) {
        case NodeType.mapping:
            auto o = Json.emptyObject;
            foreach (Node k, Node v; n)
                o[k.as!string] = convert(v);
            return o;
        case NodeType.sequence:
            auto a = Json.emptyArray;
            foreach (Node v; n)
                a ~= convert(v);
            return a;
        case NodeType.boolean:
            return Json(n.as!bool);
        case NodeType.integer:
            return Json(n.as!long);
        case NodeType.decimal:
            return Json(n.as!double);
        case NodeType.null_:
            return Json.emptyObject;
        default:
            return Json(n.as!string);
        }
    }

    auto root = convert(Loader.fromFile(file).load());
    return root.type == Json.Type.object ? root : Json.emptyObject;
}

private immutable string[2][] envMap = [
    ["KMS_PORT", "server.port"],
    ["PORT", "server.port"], // Cloud Foundry
    ["KMS_BIND", "server.bindAddresses"],
    ["KMS_FRONTEND_DIR", "server.frontendDir"],
    ["KMS_CORS_ORIGIN", "server.corsOrigin"],
    ["KMS_LOG_LEVEL", "log.level"],
    ["KMS_LOG_REQUESTS", "log.requests"],
    ["KMS_LOG_FILE", "log.file"],
    ["KMS_STORAGE_DRIVER", "storage.driver"],
    ["KMS_DATA_DIR", "storage.dataDir"],
    ["KMS_MAX_UPLOAD_MB", "media.maxUploadMB"],
    ["KMS_QUOTA_MB", "media.quotaMB"],
    ["KMS_ALLOWED_EXTENSIONS", "media.allowedExtensions"],
    ["KMS_AUTH_MODE", "auth.mode"],
    ["KMS_TOKEN_SECRET", "auth.tokenSecret"],
    ["KMS_TOKEN_TTL_MINUTES", "auth.tokenTtlMinutes"],
    ["KMS_ADMIN_USER", "bootstrap.adminUser"],
    ["KMS_ADMIN_PASSWORD", "bootstrap.adminPassword"],
    ["KMS_DEMO_CONTENT", "bootstrap.demoContent"],
    ["KMS_PDFTOTEXT", "search.pdftotext"],
];

private bool applyEnvironment(ref Json tree, string[string] env) {
    bool any = false;
    foreach (m; envMap) {
        auto v = m[0] in env;
        if (v is null)
            continue;
        auto path = m[1].split(".");
        auto current = tree[path[0]][path[1]];
        tree[path[0]][path[1]] = convertLike(current, *v, m[0]);
        any = true;
    }
    return any;
}

/// Converts an environment string to the JSON type of the default value.
private Json convertLike(Json current, string raw, string name) {
    auto s = raw.strip;
    try {
        switch (current.type) {
        case Json.Type.int_:
            return Json(s.to!long);
        case Json.Type.bool_:
            return Json(s == "true" || s == "1" || s == "yes" || s == "on");
        case Json.Type.array:
            auto a = Json.emptyArray;
            foreach (part; s.split(","))
                if (part.strip.length)
                    a ~= Json(part.strip);
            return a;
        default:
            return Json(s);
        }
    } catch (Exception e)
        throw new Exception("invalid value for " ~ name ~ ": " ~ raw);
}

/// Reads xsuaa credentials and a user-provided "kms-config" service from VCAP_SERVICES.
private bool applyVcap(ref Json tree, string vcap) {
    Json services;
    try
        services = parseJsonString(vcap);
    catch (Exception e)
        throw new Exception("VCAP_SERVICES is not valid JSON: " ~ e.msg);
    if (services.type != Json.Type.object)
        return false;
    bool any = false;
    foreach (string label, instances; services) {
        if (instances.type != Json.Type.array)
            continue;
        foreach (inst; instances) {
            auto creds = inst["credentials"];
            if (creds.type != Json.Type.object)
                continue;
            if (label == "xsuaa" || hasTag(inst, "xsuaa")) {
                tree["xsuaa"]["present"] = true;
                tree["xsuaa"]["xsappname"] = creds["xsappname"].opt!string("");
                tree["xsuaa"]["verificationKey"] = creds["verificationkey"].opt!string("");
                any = true;
            } else if (hasTag(inst, "kms-config") || inst["name"].opt!string("") == "kms-config") {
                foreach (string section, value; creds)
                    if (tree[section].type == Json.Type.object && value.type == Json.Type.object)
                        tree[section] = merge(tree[section], value);
                any = true;
            }
        }
    }
    return any;
}

private bool hasTag(Json inst, string tag) {
    auto tags = inst["tags"];
    if (tags.type != Json.Type.array)
        return false;
    foreach (t; tags)
        if (t.type == Json.Type.string && t.get!string == tag)
            return true;
    return false;
}

unittest {
    import std.file : tempDir;
    auto cfg = loadConfig(buildPath(tempDir, "kms-no-such-dir"), [
        "KMS_PORT": "9090", "KMS_DEMO_CONTENT": "false", "KMS_BIND": "127.0.0.1, ::1",
        "VCAP_SERVICES": `{"xsuaa":[{"credentials":{"xsappname":"kms-dev","verificationkey":"K"}}],`
            ~ `"user-provided":[{"name":"kms-config","credentials":{"media":{"quotaMB":5}}}]}`
    ]);
    assert(cfg.server.port == 9090);
    assert(!cfg.bootstrap.demoContent);
    assert(cfg.server.bindAddresses == ["127.0.0.1", "::1"]);
    assert(cfg.xsuaa.present && cfg.xsuaa.xsappname == "kms-dev");
    assert(cfg.media.quotaMB == 5);
    assert(cfg.sources[$ - 1] == "VCAP_SERVICES");
}
