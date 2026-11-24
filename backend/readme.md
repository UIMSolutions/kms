# kms-backend

D / vibe.d 0.10.5 service of the knowledge management system. It follows the hexagonal (Clean
Architecture) layout under `source/uim/myfiori/`; see [../uml.md](../uml.md) for the diagrams and
[../README.md](../README.md) for the features, configuration and REST API.

```bash
dub build                         # debug build -> build/kms-backend
dub build -b release --compiler=ldc2
dub test                          # unit tests + tests/integration.d
./build/kms-backend               # HTTP server on :8080 (serves ../frontend under /app/)
./build/kms-backend user-add anna editor 'Secret-Passw0rd'
./build/kms-backend reindex
```

| folder | content |
|---|---|
| `config/` | `default.json`, `default.yaml` (+ git-ignored `local.*`) |
| `data/` | runtime data: `db/`, `files/`, `audit/` (git-ignored) |
| `docs/` | developer notes |
| `tests/` | test runner and end-to-end use-case tests |
| `views/` | Diet templates (reserved for server-side pages) |
| `build/` | build output |
