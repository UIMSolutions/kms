# uim KMS: Knowledge Management System

A knowledge base for teams. It stores **articles** (Markdown) and **documents & media** (PDF, Office, images,
video, audio, archives …) in **spaces**, makes all of it findable through a built-in **full-text search
engine**, and controls access with **login, roles and user management**. All data lives in the **file
system**: no database is needed.

| part | technology | folder |
|---|---|---|
| backend | D, vibe.d 0.10.5, uim-framework 26.11.2, hexagonal / Clean Architecture | [backend/](backend/) |
| frontend | SAP Fiori 3 (`sap_fiori_3`), OpenUI5 1.136 | [frontend/](frontend/) |
| approuter | `@sap/approuter`, XSUAA (SAP BTP / Cloud Foundry) | [approuter/](approuter/) |
| deployment | MTA ([mta.yaml](mta.yaml)) | root |

Further documentation: [uml.md](uml.md) (diagrams), [nafv4.md](nafv4.md) (NAF v4 architecture description),
[backend/readme.md](backend/readme.md), [frontend/readme.md](frontend/readme.md),
[approuter/readme.md](approuter/readme.md).

---

## Features

### Login & user management
- Local login with user name / password → signed session token (HS256 JWT, default 8 h)
- Passwords hashed with PBKDF2-HMAC-SHA256 (210,000 iterations, random salt)
- Password policy: at least 10 characters with upper- and lower-case letters and a digit
- Account lock for 10 minutes after 5 failed logins; administrators can unlock early
- Forced password change for new users and after a password reset
- Roles: **reader** (read & search published content), **editor** (create / edit articles, upload media),
  **admin** (users, spaces, search index, audit trail)
- Safeguards: the last active administrator can't be deleted, demoted or deactivated, and admins can't
  delete or deactivate themselves
- Optional SSO through the SAP approuter + XSUAA: users are created on first access and their role
  follows the XSUAA role collections `KMS_Reader` / `KMS_Editor` / `KMS_Admin`

### Knowledge content
- **Spaces** group content by team, product or topic (key, name, description, icon)
- **Articles** in Markdown (headings, lists, tables, code, links, images) with summary, tags and attachments
- Lifecycle: draft → published → archived (readers see only published articles)
- **Version history**: a snapshot is taken before every change (up to 50 per article); you can preview
  and restore older versions
- Optimistic locking (`If-Match` / version) prevents silent overwrites
- View counter, "recently changed" list, popular tags

### Documents & other media
- Upload one or many files (drag & drop, file picker, raw body or `multipart/form-data`)
- Classified automatically as document, spreadsheet, presentation, image, video, audio, archive or other
- Metadata: title, description, space, tags; SHA-256 checksum; download counter
- Replace the file while keeping its id and URL (file revision counter)
- In-app preview for images, video, audio, PDF and text files; streaming downloads with HTTP Range
  support (video seeking)
- Size limit (default 100 MB), optional storage quota, optional extension allow-list; executables
  (`.exe`, `.sh`, `.bat` …) are always blocked
- Safe delivery: `Content-Disposition`, `X-Content-Type-Options: nosniff`, sandboxing CSP, and only
  types that can't run scripts are shown inline

### Search engine
- Inverted index with **BM25** ranking; field weights title ×3, tags ×2, summary ×1.5, body ×1
- Indexes article text **and the text inside uploaded files**: TXT/MD/CSV/JSON/XML/HTML/RTF, DOCX, PPTX,
  XLSX, ODT/ODP/ODS (built in) and PDF (through `pdftotext` from poppler-utils, if installed). Text
  is extracted in a background queue.
- Query syntax: `vpn client` (all words), `"exact phrase"`, `-exclude`, `prefix*`
- Unicode-aware tokenizer, case and diacritics folding (`Größe` = `grosse`), English and German stop
  words, light plural stemming
- **Fuzzy matching** for typos (edit distance 1–2) with "did you mean" suggestions
- **Facets** (type, space, tag, media type) and filters, highlighted snippets, paging
- **Auto-complete** in the header search field
- Results depend on permissions: drafts and archived articles appear only for editors and admins
- The index lives in memory, is rebuilt from the file system at start-up and can be rebuilt by an admin

### Operations
- File system storage: one human-readable JSON file per entity, written atomically
- Audit trail (JSON lines per month) and request metrics (`/api/v1/admin/metrics`, Prometheus `/metrics`)
- Health check `/healthz`
- Read-only **OData v4** service (`/odata/v4/kms/`) for Fiori elements, SAP Analytics Cloud or Excel
- Admin CLI: `user-add`, `user-passwd`, `user-role`, `user-list`, `reindex`
- English and German user interface

---

## Quick start (local)

Prerequisites: `dmd` or `ldc2` and `dub`; optional `pdftotext` (package `poppler-utils`) for PDF search.

```bash
cd backend
dub build                                       # -> build/kms-backend
KMS_ADMIN_PASSWORD='Admin-Passw0rd' ./build/kms-backend
```

Open <http://localhost:8080/> and sign in as `admin`. Without `KMS_ADMIN_PASSWORD`, the server generates a
password on the first start, logs it once and asks you to change it at the first login. The first start
also creates two demo spaces with three articles (turn this off with `KMS_DEMO_CONTENT=false`).

The backend serves the frontend from `../frontend` under `/app/`. To develop the UI with the UI5 tooling
instead (port 8081, with the API proxied to 8080):

```bash
cd frontend && npm install && npm start
```

Run the tests:

```bash
cd backend && dub test        # unit tests + end-to-end use-case tests (17 modules)
```

Open `frontend/test/testsuite.qunit.html` (through `npm test`) for the frontend QUnit tests.

---

## Data on disk

```
backend/data/                       (KMS_DATA_DIR)
├── db/
│   ├── users/<id>.json
│   ├── spaces/<id>.json
│   ├── articles/<id>.json
│   ├── article_versions/<id>.json
│   └── documents/<id>.json         metadata + extracted full text
├── files/<2-char fan-out>/<id>     binary content of documents & media
└── audit/audit-YYYY-MM.jsonl       audit trail
```

Back up the folder by copying it (`tar`, `rsync`, snapshots). Stop the server while restoring.
The search index is never stored: it is rebuilt from `db/` at every start.

---

## Configuration

Settings are layered; later layers win:

1. defaults in `AppConfig` ([appconfig.d](backend/source/uim/myfiori/infrastructure/configuration/appconfig.d))
2. `backend/config/default.json`, then `default.yaml`
3. `backend/config/local.json` / `local.yaml` (git-ignored, for your machine)
4. environment variables `KMS_*`
5. `VCAP_SERVICES`: bound `xsuaa` service and a user-provided service tagged `kms-config`

| variable | default | meaning |
|---|---|---|
| `KMS_PORT` / `PORT` | 8080 | HTTP port |
| `KMS_BIND` | `0.0.0.0` | bind addresses (comma separated) |
| `KMS_DATA_DIR` | `data` | storage root |
| `KMS_STORAGE_DRIVER` | `file` | `file` or `memory` (tests / demos) |
| `KMS_FRONTEND_DIR` | `../frontend` | serve the UI under `/app/` (empty = off) |
| `KMS_CORS_ORIGIN` | – | allowed origin for a separately served UI |
| `KMS_AUTH_MODE` | `local` | `local` or `xsuaa` |
| `KMS_TOKEN_SECRET` | random per start | HS256 secret (≥ 32 chars); **set it in production** |
| `KMS_TOKEN_TTL_MINUTES` | 480 | session lifetime |
| `KMS_ADMIN_USER` / `KMS_ADMIN_PASSWORD` | `admin` / generated | initial administrator |
| `KMS_DEMO_CONTENT` | `true` | seed demo spaces and articles on first start |
| `KMS_MAX_UPLOAD_MB` | 100 | maximum file size |
| `KMS_QUOTA_MB` | 0 | total storage quota (0 = unlimited) |
| `KMS_ALLOWED_EXTENSIONS` | – | allow-list, e.g. `.pdf,.docx,.png` |
| `KMS_PDFTOTEXT` | `pdftotext` | PDF text extractor binary (empty = off) |
| `KMS_LOG_LEVEL` / `KMS_LOG_FILE` / `KMS_LOG_REQUESTS` | `info` / – / `true` | logging |
| `KMS_CONFIG_DIR` | `config` | where the config files are read from |

---

## REST API (`/api/v1`)

All endpoints except `auth/config`, `auth/login` and `/healthz` require `Authorization: Bearer <token>`.
Errors use the shape `{"error":{"code":"404","message":"…"}}`.

| method & path | role | purpose |
|---|---|---|
| `GET auth/config` | – | login mode |
| `POST auth/login` `{username,password}` | – | → `{token, expiresIn, user}` |
| `GET auth/me`, `PATCH auth/profile`, `POST auth/password` | any | own account |
| `GET/POST users`, `GET/PATCH/DELETE users/{id}` | admin | user management |
| `POST users/{id}/password`, `POST users/{id}/unlock` | admin | reset password, unlock |
| `GET spaces`, `GET spaces/{id}` | any | spaces with counts |
| `POST spaces`, `PATCH/DELETE spaces/{id}` | admin | manage spaces (only empty spaces can be deleted) |
| `GET articles?space&status&tag&author&q&orderBy&skip&top` | any | list |
| `POST articles`, `PATCH articles/{id}` (`If-Match`) | editor | create / update |
| `GET articles/{id}?view=true` | any | read (+ count a view) |
| `POST articles/{id}/publish` · `/archive` · `/reopen` | editor | lifecycle |
| `GET articles/{id}/versions`, `POST articles/{id}/versions/{vid}/restore` | editor | history |
| `DELETE articles/{id}` | author / admin | delete |
| `GET documents?space&kind&tag&q&orderBy&skip&top`, `GET documents/{id}` | any | list / metadata |
| `POST documents` | editor | upload (raw body + `X-File-Name`, `X-Title`, `X-Space`, `X-Tags`, `X-Description`, or multipart) |
| `PATCH documents/{id}`, `PUT documents/{id}/content` | editor | metadata / replace file |
| `GET documents/{id}/content[?download=true]` | any | stream the file (Range supported) |
| `DELETE documents/{id}` | uploader / admin | delete (also removes it from articles) |
| `GET search?q&kind&space&tag&media&skip&top` | any | full-text search with facets |
| `GET search/suggest?q` | any | auto-complete |
| `GET stats` | any | dashboard figures |
| `POST admin/reindex`, `GET admin/audit`, `GET admin/metrics` | admin | operations |

Examples:

```bash
TOKEN=$(curl -s -X POST localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin-Passw0rd"}' | jq -r .token)
curl -X POST localhost:8080/api/v1/documents -H "Authorization: Bearer $TOKEN" \
  -F file=@handbook.pdf -F tags=hr,onboarding
curl "localhost:8080/api/v1/search?q=%22travel%20expenses%22%20-draft" -H "Authorization: Bearer $TOKEN"
curl "localhost:8080/odata/v4/kms/Articles?\$top=10&\$count=true" -H "Authorization: Bearer $TOKEN"
```

---

## Deployment to SAP BTP (Cloud Foundry)

```bash
mbt build                      # builds backend (ldc2 release), packs frontend into the approuter
cf deploy mta_archives/uim-kms_1.0.0.mtar
```

- The approuter is the single entry point (`/app/` UI, `/api/v1/`, `/odata/`), protected by XSUAA.
- Assign the role collections `KMS_Reader`, `KMS_Editor` or `KMS_Admin` to users in the BTP cockpit.
- The backend runs with `KMS_AUTH_MODE=xsuaa`. It validates the forwarded RS256 token and provisions users
  on first access.
- **Persistence:** Cloud Foundry container disks are temporary. Mount a volume service and point
  `KMS_DATA_DIR` at it, or run the backend on a VM or Kubernetes with a persistent volume. Run one
  instance only, because the file store and the search index belong to one process.
- Put secrets (`KMS_TOKEN_SECRET`, `KMS_ADMIN_PASSWORD`) into a user-provided service tagged `kms-config`
  or set them with `cf set-env`. Never put them in `mta.yaml`.

Local approuter test: copy real XSUAA credentials into `approuter/default-env.json` (git-ignored), start the
backend with `KMS_AUTH_MODE=xsuaa` and a matching `VCAP_SERVICES`, then run `npm start` in `approuter/`.

---

## Project layout

```
kms/
├── mta.yaml                    MTA descriptor (backend + frontend + approuter + XSUAA)
├── README.md  uml.md  nafv4.md
├── backend/                    D / vibe.d service
│   ├── dub.sdl  config/  data/  docs/  tests/  views/  build/
│   └── source/uim/myfiori/
│       ├── domain/             entities, types, enumerations, services (search engine, policy), exceptions
│       ├── application/        usecases (interactors), services, dtos
│       ├── ports/              usecases, services, repositories, storages, gateways, messaging
│       ├── infrastructure/     configuration, logging, security, clients, monitoring, workers
│       ├── persistence/        storages (file / memory), records, mappers, repositories
│       ├── presentation/       http (REST), odata, cli
│       └── composition.d       composition root
├── frontend/                   OpenUI5 app (Component.js, manifest.json, view/, controller/, model/, i18n/, test/)
└── approuter/                  xs-app.json, xs-security.json, package.json
```

## Limits and next steps

- The search index is held in memory. That is fine for tens of thousands of items; beyond that, plug
  a dedicated engine (OpenSearch, Meilisearch) in behind the same `SearchIndexer`.
- The file store is built for a single instance. A database or object-store adapter can implement the
  `DocumentStorage` / `BlobStorage` ports without changing the domain or the use cases.
- Possible extensions: per-space permissions, comments and ratings, article templates, OCR for
  scanned PDFs and images, malware scanning of uploads.
