# kms-frontend

SAP Fiori 3 (`sap_fiori_3`) / OpenUI5 1.136 app of the knowledge management system
(namespace `uim.myfiori.kms`).

- served by the backend under `http://localhost:8080/app/` (no build step), or
- `npm install && npm start`: UI5 tooling on port 8081, proxying `/api` and `/odata` to `localhost:8080`
- `npm test`: QUnit tests (`test/unit/markdown.js`, `test/unit/formatter.js`)

| folder | content |
|---|---|
| `view/`, `controller/` | Login, Home, Search, Articles, ArticleDetail, ArticleEdit, Documents, Spaces, Users, Admin + dialogs |
| `model/` | `api.js` (REST client, token / CSRF), `models.js`, `formatter.js`, `markdown.js` (safe Markdown renderer) |
| `i18n/` | English and German texts |
| `localService/` | OData `$metadata` and mock data of the read service |
| `css/` | Markdown, snippet and drop-zone styles |
| `test/` | QUnit test suite |

Authentication: local login stores the bearer token in `sessionStorage`. Behind the approuter, the
session cookie is used and the CSRF token is fetched automatically.
