# uim KMS: architecture description (NAF v4)

This description follows the NATO Architecture Framework v4 grid (viewpoint families C, S, L, P, Lr).
It describes the knowledge management system **as built** in this repository. Diagrams are in
[uml.md](uml.md); operation and setup are in [README.md](README.md).

## A: Architecture metadata

| item | value |
|---|---|
| Name | uim KMS: Knowledge Management System |
| Version | 1.0.0 (2026-11) |
| Purpose | Capture, organise, find and share organisational knowledge (articles, documents, media) |
| Scope | Backend service, Fiori web frontend, approuter / XSUAA integration, file system persistence |
| Architecture style | Hexagonal / Clean Architecture (ports & adapters), single-process service |
| Stakeholders | Readers (employees), editors (knowledge owners), administrators (IT / KM team), operators |
| Standards | HTTP/1.1, REST/JSON, OData v4 (read), JWT (RFC 7519), OAuth 2.0 / XSUAA, PBKDF2 (RFC 8018), Markdown (CommonMark subset), SAP Fiori 3 design |
| Constraints | No database; data must be readable on disk; runs on Linux, as a stand-alone server or on SAP BTP |

## C: Concepts (capabilities)

### C1: Capability taxonomy

| id | capability | description |
|---|---|---|
| C1 | Identity & access management | sign in, sessions, roles, user lifecycle |
| C1.1 | Authentication | local password login (PBKDF2) or XSUAA SSO via the approuter |
| C1.2 | Authorisation | role model reader < editor < admin, enforced by `AccessPolicy` |
| C1.3 | User administration | create, edit, deactivate, delete, reset password, unlock |
| C1.4 | Account protection | password policy, lockout after 5 failures, forced password change |
| C2 | Knowledge authoring | write and maintain articles |
| C2.1 | Article editing | Markdown with live preview, tags, summary, attachments |
| C2.2 | Lifecycle | draft → published → archived, reopen |
| C2.3 | Versioning | snapshot per change, preview and restore, optimistic locking |
| C3 | Document & media management | store and serve files of any type |
| C3.1 | Upload | single / multi-file, drag & drop, multipart and raw uploads |
| C3.2 | Classification & metadata | media kind detection, title, description, tags, space |
| C3.3 | Delivery | preview, streaming download with Range, safe content headers |
| C3.4 | Governance | size limit, quota, extension allow / block lists, checksums |
| C4 | Knowledge organisation | spaces, tags, attachments between articles and documents |
| C5 | Knowledge discovery | full-text search engine |
| C5.1 | Indexing | articles and extracted file text (PDF, Office, OpenDocument, text formats) |
| C5.2 | Retrieval | BM25 ranking, phrases, exclusion, prefix, fuzzy matching |
| C5.3 | Navigation | facets, filters, suggestions, highlighted snippets, recent items, popular tags |
| C6 | Operations | configuration, audit trail, metrics, health, CLI, backup by copying files |

### C2: Enterprise vision

Knowledge should be **findable within seconds**, **owned by the people who create it** and **independent of
proprietary storage**. The system therefore indexes file contents as well as metadata, gives editors
self-service authoring, and keeps every record as a plain JSON file next to the original binary.

### C3: Capability dependencies

C5 (discovery) depends on C2/C3 (content) and C1.2 (visibility). C2 and C3 depend on C1 (identity) and C4
(organisation). C6 supports all capabilities.

## S: Service specifications

### S1: Service taxonomy

| service | interface | consumers | capability |
|---|---|---|---|
| Authentication service | `POST /api/v1/auth/login`, `GET auth/me`, `POST auth/password`, `PATCH auth/profile` | Fiori app, scripts | C1.1, C1.4 |
| User management service | `/api/v1/users[/{id}[/password\|/unlock]]` | Admin UI, CLI | C1.3 |
| Space service | `/api/v1/spaces` | all UIs | C4 |
| Article service | `/api/v1/articles` (+ publish, archive, reopen, versions, restore) | Fiori app | C2 |
| Document & media service | `/api/v1/documents` (+ `/content`) | Fiori app, integrations | C3 |
| Search service | `/api/v1/search`, `/api/v1/search/suggest` | Fiori app, integrations | C5 |
| Statistics service | `/api/v1/stats` | Home dashboard | C5.3, C6 |
| Administration service | `/api/v1/admin/{reindex,audit,metrics}` | Admin UI | C6 |
| Analytics read service | OData v4 `/odata/v4/kms/{Spaces,Articles,Documents}` with `$metadata` | Fiori elements, SAC, Excel | C4, C5 |
| Health / monitoring | `/healthz`, `/metrics` (Prometheus) | Cloud Foundry, monitoring | C6 |
| Administration CLI | `kms-backend user-add\|user-passwd\|user-role\|user-list\|reindex` | operators | C1.3, C6 |

### S2: Service interfaces (driving ports)

`AuthUseCase`, `UserUseCase`, `SpaceUseCase`, `ArticleUseCase`, `DocumentUseCase`, `SearchUseCase`,
`StatisticsUseCase` in [ports/usecases](backend/source/uim/myfiori/ports/usecases/package.d). Every
operation takes the calling `Principal` as its first argument, so authorisation never depends on the
transport.

### S3: Service quality (policies)

| aspect | policy |
|---|---|
| Confidentiality | bearer tokens (HS256 local / RS256 XSUAA); drafts are hidden from readers (404, not 403) |
| Integrity | optimistic locking (`If-Match`), atomic file writes, SHA-256 per file |
| Availability | single instance; restart rebuilds the index in seconds for typical volumes |
| Accountability | audit events (logins, failures, user / space / article / document changes) as JSON lines |
| Privacy | search queries are counted but not written to the audit trail |
| Error contract | `{"error":{"code","message"}}`; 400 / 401 / 403 / 404 / 409 / 413 / 423 / 500 |

### S4: Service functions (selected)

- **Search**: parse query → match clauses (exact, prefix, fuzzy, phrase) → AND → visibility → facets →
  filters → BM25 ranking → page → snippets.
- **Upload**: authorise → sanitise file name → check size / extension / quota → store blob → save
  metadata → index metadata → event `document.uploaded` → asynchronous text extraction → re-index.

## L: Logical specifications

### L1: Node types (logical)

| node | role |
|---|---|
| Browser client | Fiori 3 / OpenUI5 single-page app |
| Approuter (optional) | entry point, OAuth2 login, CSRF, routing |
| KMS service | the backend process (all layers below) |
| Identity provider (optional) | XSUAA |
| File store | data directory (JSON records, binaries, audit) |
| Text extraction tool (optional) | `pdftotext` |

### L2: Logical scenario

Editor uploads a manual → the service stores it and returns at once → the worker extracts the text →
a reader searches a phrase from page 12 → the result appears with a highlighted snippet → the reader
previews the PDF in the browser.

### L3: Logical interactions

See the sequence diagrams in [uml.md](uml.md) §4–5.

### L4: Logical activities by layer

| layer | responsibilities | key elements |
|---|---|---|
| Domain | business rules without I/O | `User` (lockout), `Article` (lifecycle, attachments), `Document`, `AccessPolicy`, `SearchEngine`, tokenizer, validation rules |
| Application | orchestrate use cases | `*Interactor`, `SearchIndexer`, `TextExtractionService`, `TokenIdentityService`, `BootstrapService`, `EventBus`, DTOs |
| Ports | contracts | repositories, storages, services, gateways, messaging, use cases |
| Infrastructure | technical services | configuration loader (JSON / YAML / env / VCAP), PBKDF2, JWT, XSUAA validation, MIME types, text extraction, audit log, metrics, background worker |
| Persistence | data access | `FileDocumentStorage`, `FileBlobStorage`, memory variants, records, mappers, repositories |
| Presentation | protocols | REST controllers, OData v4 read service, static UI hosting, CLI |

### L5: Logical states

Article: `draft`, `published`, `archived` ([uml.md](uml.md) §6). User: active / inactive, locked until
time T, must-change-password flag.

### L7: Logical data model

| entity | key attributes | relations |
|---|---|---|
| User | id, username (unique), role, active, passwordHash, externalId | author of Article, uploader of Document |
| Space | id, key (unique), name | contains Articles and Documents |
| Article | id, title, body, tags, status, version | in 1 Space; attaches n Documents; has n ArticleVersions |
| ArticleVersion | id, articleId, version, snapshot fields | belongs to 1 Article |
| Document | id, fileName, mimeType, kind, size, sha256, tags, text | in 0..1 Space; attached to n Articles |
| Audit event | at, type, actor, subject, detail | refers to any entity |

### L8: Logical constraints

- user names 3–40 chars `[a-z0-9._-]`, space keys 2–20 chars `[A-Z0-9]`, ≤ 30 tags of ≤ 48 chars
- article title ≤ 200 chars, body ≤ 1 MB; at most 50 versions kept per article
- a space can be deleted only when empty; at least one active administrator must remain
- uploads ≤ `media.maxUploadMB`; total ≤ `media.quotaMB`; executables blocked

## P: Physical resource specifications

### P1: Resource types

| resource | implementation |
|---|---|
| Backend executable | `kms-backend` (D, dmd / ldc2, vibe.d 0.10.5, uim-framework 26.11.2, dyaml) |
| Frontend | static OpenUI5 app (served by the backend under `/app/` or by the approuter) |
| Approuter | Node.js ≥ 20, `@sap/approuter` |
| XSUAA service | `kms-uaa` (plan `application`), scopes Reader / Editor / Admin |
| Storage | file system directory, see the layout in [README.md](README.md#data-on-disk) |
| PDF extractor | poppler-utils `pdftotext` (optional) |

### P2: Resource structure

```
backend/source/uim/myfiori/{domain,application,ports,infrastructure,persistence,presentation}
backend/{config,data,docs,tests,views,build}
frontend/{view,controller,model,i18n,localService,test,data,css}
approuter/{xs-app.json,xs-security.json,package.json,default-env.json}
mta.yaml
```

### P3: Resource connectivity

| from | to | protocol | security |
|---|---|---|---|
| Browser | Approuter / backend | HTTPS | session cookie + CSRF (approuter) or bearer token |
| Approuter | Backend | HTTPS (destination `kms-backend`) | forwarded XSUAA JWT |
| Backend | XSUAA | none at runtime (offline RS256 check with the bound verification key) | – |
| Backend | file system | POSIX I/O | process user permissions |
| Backend | pdftotext | local process (timeout) | temporary file, deleted afterwards |

### P4: Resource configuration

[backend/config/default.json](backend/config/default.json), `default.yaml`, `local.*`, `KMS_*` environment
variables and `VCAP_SERVICES`, merged in this order. The full table is in [README.md](README.md#configuration).

### P5: Physical deployment

- **Stand-alone**: one Linux host or container running `kms-backend` with a persistent `data/` directory;
  a TLS-terminating reverse proxy in front.
- **SAP BTP**: `mbt build` + `cf deploy` deploys approuter, backend (`binary_buildpack`) and the XSUAA
  instance. The data directory must be on a persistent volume, and the backend runs as one instance.

## Lr: Lines of development (roadmap)

| step | content |
|---|---|
| 1.0 (this release) | login & user management, spaces, articles with history, documents & media, full-text search with file content, OData read, audit, metrics, CLI, EN/DE UI |
| 1.1 | per-space permissions (space readers / editors), comments, article templates |
| 1.2 | OCR for scanned PDFs and images, malware scan hook for uploads, thumbnail generation |
| 2.0 | pluggable storage and search adapters (PostgreSQL / object store / OpenSearch) behind the existing ports for horizontal scaling |

## Trace: capability → service → resource

| capability | service | logical element | physical resource |
|---|---|---|---|
| C1.1 Authentication | Authentication service | `AuthInteractor`, `TokenIdentityService` | `Pbkdf2PasswordHasher`, `HmacTokenIssuer`, `XsuaaTokenValidator`, XSUAA |
| C1.2 Authorisation | all services | `AccessPolicy`, `Principal` | backend process |
| C1.3 User administration | User management service, CLI | `UserInteractor` | `db/users/*.json` |
| C1.4 Account protection | Authentication service | `User.loginFailed`, `checkPasswordPolicy` | `db/users/*.json` |
| C2 Knowledge authoring | Article service | `ArticleInteractor`, `Article`, `ArticleVersion` | `db/articles`, `db/article_versions` |
| C3 Document & media management | Document & media service | `DocumentInteractor`, `Document`, `MediaKind` | `db/documents`, `files/` |
| C4 Organisation | Space service, OData | `SpaceInteractor`, tags, attachments | `db/spaces` |
| C5 Discovery | Search service, suggest, stats | `SearchEngine`, `SearchIndexer`, `TextExtractionService` | in-memory index, `CompositeTextExtractor`, `pdftotext` |
| C6 Operations | Admin, health, metrics, CLI | `AuditLog`, `RequestMetrics`, `loadConfig` | `audit/*.jsonl`, `/metrics`, config files |
