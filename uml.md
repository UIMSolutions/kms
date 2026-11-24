# uim KMS: UML

Diagrams in Mermaid (rendered by GitHub, GitLab and VS Code). Source code:
[backend/source/uim/myfiori/](backend/source/uim/myfiori/), [frontend/](frontend/).

## 1. Component diagram (hexagonal layers)

```mermaid
flowchart LR
  subgraph Presentation["presentation (driving adapters)"]
    AUTHC[http/AuthController]
    USRC[http/UserController]
    SPC[http/SpaceController]
    ARTC[http/ArticleController]
    DOCC[http/DocumentController]
    SRC[http/SearchController]
    ADMC[http/AdminController]
    OD[odata/ODataService]
    CLI[cli/AdminCli]
    SRV[http/HttpServer + static /app/]
  end
  subgraph Ports["ports"]
    UC[[usecases: Auth, User, Space, Article, Document, Search, Statistics]]
    PS[[services: IdentityService, Clock, IdGenerator, PasswordHasher, TokenIssuer, ExternalTokenValidator, MimeTypes]]
    RP[[repositories: User, Space, Article, ArticleVersion, Document]]
    ST[[storages: DocumentStorage, BlobStorage]]
    GW[[gateways: TextExtractor]]
    MS[[messaging: EventPublisher, EventHandler]]
  end
  subgraph Application["application"]
    INT[usecases: *Interactor]
    APS[services: TokenIdentityService, SearchIndexer, TextExtractionService, BootstrapService, DtoMapper, EventBus]
    DTO[dtos]
  end
  subgraph Domain["domain"]
    ENT[entities: User, Space, Article, ArticleVersion, Document]
    TYP[types: Principal, SearchQuery, tags, username rules, Page]
    ENU[enumerations: Role, ArticleStatus, MediaKind, ItemKind]
    DSV[services: SearchEngine, tokenizer, AccessPolicy]
    EXC[exceptions]
  end
  subgraph Infrastructure["infrastructure"]
    CFG[configuration: AppConfig, loadConfig]
    SEC[security: Pbkdf2PasswordHasher, HmacTokenIssuer, XsuaaTokenValidator]
    CLT[clients: SystemClock, UuidGenerator, ExtensionMimeTypes, CompositeTextExtractor]
    MON[monitoring: RequestMetrics, AuditLog]
    WRK[workers: TextExtractionWorker]
    LOG[logging]
  end
  subgraph Persistence["persistence (driven adapters)"]
    REPO[repositories: Storage*Repository]
    MAP[mappers]
    REC[records]
    STO[storages: FileDocumentStorage, MemoryStorage, FileBlobStorage, MemoryBlobStorage]
  end
  COMP[(composition.d<br/>Container)]

  Presentation --> UC
  Presentation --> PS
  INT -. implements .-> UC
  INT --> RP & ST & PS & MS & APS
  APS --> GW & RP
  Application --> Domain
  REPO -. implements .-> RP
  REPO --> MAP --> REC
  REPO --> ST
  STO -. implements .-> ST
  SEC -. implements .-> PS
  CLT -. implements .-> PS & GW
  MON -. implements .-> MS
  WRK -. implements .-> MS
  COMP --> Presentation & Application & Infrastructure & Persistence
```

Dependency rule: arrows point inward. `domain` imports only Phobos. `application` imports `domain`
and `ports`. Adapters (`presentation`, `persistence`, `infrastructure`) depend on ports, and the
composition root is the only module that knows every concrete class.

## 2. Domain class diagram

```mermaid
classDiagram
  direction LR
  class User {
    +string id
    +string username
    +string displayName
    +string email
    +Role role
    +bool active
    +string passwordHash
    +string externalId
    +bool mustChangePassword
    +uint failedLogins
    +SysTime lockedUntil
    +SysTime lastLoginAt
    +long version_
    +isLocked(now) bool
    +loginFailed(now)
    +loginSucceeded(now)
  }
  class Space {
    +string id
    +string key
    +string name
    +string description
    +string icon
  }
  class Article {
    +string id
    +string spaceId
    +string title
    +string summary
    +string body
    +string[] tags
    +string[] attachmentIds
    +ArticleStatus status
    +string authorId
    +ulong views
    +long version_
    +publish(now)
    +archive()
    +reopen()
    +attach(docId)
    +detach(docId)
  }
  class ArticleVersion {
    +string id
    +string articleId
    +long version_
    +string title
    +string body
    +string[] tags
    +string changedBy
    +SysTime changedAt
  }
  class Document {
    +string id
    +string spaceId
    +string title
    +string fileName
    +string mimeType
    +MediaKind kind
    +ulong size
    +string sha256
    +string[] tags
    +string blobKey
    +string text
    +bool textExtracted
    +uint fileRevision
    +ulong downloads
  }
  class Role {
    <<enumeration>>
    reader
    editor
    admin
  }
  class ArticleStatus {
    <<enumeration>>
    draft
    published
    archived
  }
  class MediaKind {
    <<enumeration>>
    document
    spreadsheet
    presentation
    image
    video
    audio
    archive
    other
  }
  class Principal {
    <<value>>
    +string userId
    +string username
    +Role role
    +can(Role) bool
  }
  class AccessPolicy {
    <<domain service>>
    +canReadArticle(p, a) bool
    +canWrite(p) bool
    +canDelete(p, ownerId) bool
    +requireAdmin(p)
  }
  class SearchEngine {
    <<domain service>>
    -Stored[string] docs
    -double[string][string] postings
    +put(IndexEntry)
    +remove(id)
    +search(SearchQuery, visible) SearchResult
    +suggest(prefix) string[]
  }

  Space "1" o-- "*" Article : contains
  Space "1" o-- "*" Document : contains
  Article "1" *-- "*" ArticleVersion : history
  Article "*" --> "*" Document : attachments
  User "1" --> "*" Article : author
  User "1" --> "*" Document : uploader
  User --> Role
  Article --> ArticleStatus
  Document --> MediaKind
  AccessPolicy ..> Principal
  SearchEngine ..> Article : indexes
  SearchEngine ..> Document : indexes
```

## 3. Ports and adapters (class diagram)

```mermaid
classDiagram
  direction TB
  class DocumentStorage {
    <<interface>>
    +list(collection) Json[]
    +get(collection, id) Json
    +put(collection, id, Json)
    +remove(collection, id) bool
  }
  class BlobStorage {
    <<interface>>
    +put(key, data) BlobInfo
    +get(key) ubyte[]
    +localPath(key) string
    +usedBytes() ulong
  }
  class TextExtractor {
    <<interface>>
    +extract(fileName, mime, data) string
  }
  class IdentityService {
    <<interface>>
    +authenticate(token) Principal
  }
  class MemoryStorage
  class FileDocumentStorage
  class FileBlobStorage
  class MemoryBlobStorage
  class CompositeTextExtractor
  class TokenIdentityService
  class HmacTokenIssuer
  class XsuaaTokenValidator
  MemoryStorage ..|> DocumentStorage
  FileDocumentStorage --|> MemoryStorage
  FileBlobStorage ..|> BlobStorage
  MemoryBlobStorage ..|> BlobStorage
  CompositeTextExtractor ..|> TextExtractor
  TokenIdentityService ..|> IdentityService
  TokenIdentityService --> HmacTokenIssuer
  TokenIdentityService --> XsuaaTokenValidator

  class DocumentUseCase { <<interface>> }
  class DocumentInteractor
  DocumentInteractor ..|> DocumentUseCase
  DocumentInteractor --> DocumentRepository
  DocumentInteractor --> BlobStorage
  DocumentInteractor --> SearchIndexer
  DocumentInteractor --> EventPublisher
  class DocumentRepository { <<interface>> }
  class StorageDocumentRepository
  StorageDocumentRepository ..|> DocumentRepository
  StorageDocumentRepository --> DocumentStorage
  class EventPublisher { <<interface>> }
  class EventBus
  EventBus ..|> EventPublisher
  EventBus --> AuditLog
  EventBus --> TextExtractionWorker
  TextExtractionWorker --> TextExtractionService
  TextExtractionService --> TextExtractor
  TextExtractionService --> SearchIndexer
  SearchIndexer --> SearchEngine
```

## 4. Sequence: login

```mermaid
sequenceDiagram
  actor U as User
  participant UI as Fiori app (Login view)
  participant AC as AuthController
  participant AI as AuthInteractor
  participant UR as UserRepository
  participant PH as Pbkdf2PasswordHasher
  participant TI as HmacTokenIssuer
  U->>UI: user name + password
  UI->>AC: POST /api/v1/auth/login
  AC->>AI: login(username, password)
  AI->>UR: byUsername()
  alt unknown user
    AI->>PH: verify(dummy) (same timing)
    AI-->>AC: UnauthorizedException → 401
  else locked (5 failures)
    AI-->>AC: LockedException → 423
  else wrong password
    AI->>UR: save(failedLogins+1)
    AI-->>AC: 401
  else ok
    AI->>PH: verify(password, hash)
    AI->>UR: save(lastLoginAt)
    AI->>TI: issue(claims, exp)
    AI-->>AC: LoginResult{token, user}
    AC-->>UI: 200 JSON
    UI->>UI: keep token (sessionStorage), load spaces
    opt mustChangePassword
      UI->>U: "change password" dialog
    end
  end
```

## 5. Sequence: upload, text extraction and search

```mermaid
sequenceDiagram
  actor E as Editor
  participant UI as Documents view
  participant DC as DocumentController
  participant DI as DocumentInteractor
  participant BS as FileBlobStorage
  participant DR as DocumentRepository
  participant SI as SearchIndexer / SearchEngine
  participant EB as EventBus
  participant W as TextExtractionWorker
  participant TX as CompositeTextExtractor
  E->>UI: drop files
  UI->>DC: POST /api/v1/documents (raw body, X-File-Name …)
  DC->>DI: upload(principal, input, bytes)
  DI->>DI: check role, name, extension, size, quota
  DI->>BS: put(id, bytes) → size, sha256
  DI->>DR: save(document)
  DI->>SI: index(document) (title, tags, description)
  DI->>EB: publish(document.uploaded)
  EB->>W: handle() → enqueue(id)
  DC-->>UI: 201 DocumentDto
  W-)TX: extract(pdf / docx / text …)
  TX--)W: plain text
  W->>DR: save(text, textExtracted)
  W->>SI: index(document) (full text)
  E->>UI: search "travel expenses"
  UI->>SI: GET /api/v1/search?q=…
  SI-->>UI: hits (BM25), snippets, facets
```

## 6. State machine: article lifecycle

```mermaid
stateDiagram-v2
  [*] --> draft : create (editor)
  draft --> published : publish
  published --> archived : archive
  published --> draft : reopen
  archived --> draft : reopen
  archived --> published : publish
  draft --> draft : update (snapshot → version history)
  published --> published : update / restore version
  draft --> [*] : delete (author / admin)
  published --> [*] : delete
  archived --> [*] : delete
```

## 7. Search engine internals

```mermaid
flowchart LR
  Q["query text<br/>vpn &quot;remote work&quot; -draft conf*"] --> P[parseQuery]
  P --> T[terms]
  P --> PH[phrases]
  P --> PR[prefixes]
  P --> EX[excluded]
  T -->|known| BM[BM25 per term]
  T -->|unknown| FZ[fuzzy: edit distance ≤ 1–2] --> BM
  PR --> EXP[expand vocabulary ≤ 64] --> BM
  PH --> SEQ[token sequence check] --> BM
  BM --> AND[intersect clauses]
  EX --> AND
  AND --> VIS[visibility: role / status]
  VIS --> FAC[facets: kind, space, tag, media]
  VIS --> FIL[filters] --> SORT[sort by score] --> PAGE[skip / top] --> SNIP[snippets + highlight]
```

Index structure: `postings[term][docId] = weighted tf` (title 3, tag 2, summary 1.5, text 1). The engine
also keeps per-document token lists for phrase matching and weighted lengths for the BM25 length
normalisation (k1 = 1.2, b = 0.75).

## 8. Frontend structure

```mermaid
flowchart TB
  IDX[index.html<br/>OpenUI5 1.136 · sap_fiori_3] --> COMP[Component.js<br/>session restore · route guard]
  COMP --> APP[App.view<br/>ToolPage · header search with suggestions · side navigation · user menu]
  APP --> NAV[NavContainer pageContainer]
  NAV --> LOGIN[Login] & HOME[Home: tiles, recent, tags] & SEARCH[Search: facets, snippets]
  NAV --> ARTS[Articles] --> ART[ArticleDetail: Markdown, history] --> EDIT[ArticleEdit: write / preview / attachments]
  NAV --> DOCS[Documents: drag & drop upload, preview, replace] & SPACES[Spaces] & USERS[Users] & ADMIN[Admin: metrics, audit, reindex]
  COMP --> M[model/: api.js · models.js · formatter.js · markdown.js]
```

## 9. Deployment

```mermaid
flowchart LR
  B[Browser] -->|HTTPS| AR[kms-approuter<br/>Node.js · XSUAA login · CSRF]
  AR -->|/app/*| RES[(static frontend<br/>resources/)]
  AR -->|/api/v1/*, /odata/* + JWT| BE[kms-backend<br/>D / vibe.d binary]
  AR <-->|OAuth2| UAA[(XSUAA<br/>kms-uaa)]
  BE -->|verify RS256| UAA
  BE --> FS[(persistent volume<br/>KMS_DATA_DIR)]
  BE -.->|optional| PT[pdftotext]
```
