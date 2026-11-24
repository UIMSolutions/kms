# kms-approuter

Single entry point on SAP BTP: XSUAA login, CSRF protection, the static UI under `/app/` (copied to
`resources/` by the MTA build) and forwarding of `/api/v1/*` and `/odata/*` to the `kms-backend`
destination with the user's JWT.

- `xs-app.json`: routes
- `xs-security.json`: scopes `Reader`, `Editor`, `Admin`, role collections `KMS_Reader`, `KMS_Editor`, `KMS_Admin`
- `default-env.json`: local only (git-ignored); fill in the credentials of a `kms-uaa` service key

```bash
npm install && npm start     # http://localhost:5000/app/index.html
```
