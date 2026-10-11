# store-bff

A Spring Boot service on CLX Container Apps

Spring Boot 4 (Java 21, WebFlux) service on the lab Azure Container Apps environment. Created from the `spring-container-app` Backstage template; owned by `group:default/guests`.

| | dev | qa |
|---|---|---|
| Container App | `ca-lab-store-bff-d01` | `ca-lab-store-bff-q01` |
| Resource group | `rg-platform-services` | `rg-platform-services` |
| Public URL (APIM) | `https://apim-samgp-lab.azure-api.net/store-bff` | `https://apim-samgp-lab.azure-api.net/store-bff-qa` |
| Datadog | `service:store-bff env:lab-dev` | `service:store-bff env:lab-qa` |
## How it calls the orders-api API
```
caller ──► APIM /store-bff ──► this service ──API_BASE_URL + API_SUBSCRIPTION_KEY──► APIM /orders-api ──► orders-api
```
`infra/` creates an APIM subscription for this service in each environment, scoped to the `orders-api` API only, and puts its key in a Container App secret (`API_SUBSCRIPTION_KEY`). The key is never in git, a parameter file or the pipeline. `downstream/DownstreamApiClient.java` sends it on every call; add a method per API operation you need. `GET /downstream/health` proves the chain (it's separate from `/health`, so a slow API never fails this service's probes).

## Run locally
```bash
./mvnw spring-boot:run
curl http://localhost:8080/health
```

## How it ships
`.github/workflows/ci-cd.yaml` calls the shared platform pipeline (`sampgreenwell-cyber/platform-workflows`, `bicep-container-app.yaml@v1`):
1. **Pull request:** build and test (`./mvnw verify`), Snyk code and dependency scans, Docker build check. Nothing is deployed. Pull requests into `qa` must come from `dev`.
2. **Push to `dev`:** builds one image, `lab/store-bff:dev-<timestamp>-<sha>` (also tagged `tree-<git tree>`), pushes it to `samgplabacr`, then deploys `infra/` to dev.
3. **Promotion:** open a pull request from `dev` into `qa`. After it merges, the qa deployment waits until a member of `group:default/guests` approves it in the Actions run, then deploys the image dev built from the same code. qa never builds its own image, so code that never went through dev can't reach qa.

Deployment is `az deployment group create` with `infra/main.bicep` and `infra/<env>.bicepparam`. The pipeline sets `IMAGE_TAG`, which the parameter files read. Azure sign-in uses OIDC; the settings are variables on the repository's `dev` and `qa` GitHub environments.

## Common changes
- **Add a setting:** add `{ name: 'MY_SETTING', value: '...' }` to `appSettings` in each `infra/<env>.bicepparam`.
- **Add a secret:** create it in each environment's Key Vault (`kv-samgp-lab`, `kv-samgp-lab`), then add its name to `keyVaultSecretNames`. It becomes an environment variable automatically: `my-api-key` becomes `MY_API_KEY`.
- **Scale:** `minReplicas` / `maxReplicas` in the parameter files.
- **APM traces:** set `enableDatadogSidecar = true` (adds a Datadog Agent sidecar; non-prod is off for cost).
- **Only let one app call this API** (e.g. an API called only by its BFF): set `requireCallerToken = true`, `jwtAudience` to this service's app registration (application ID URI or client ID) and `allowedCallerClientId` to the caller's client ID. APIM then returns 401 without a valid Entra ID token and 403 for any other app. The caller requests a token for `jwtAudience` and sends it as `Authorization: Bearer <token>` along with the subscription key.

Preview an infrastructure change locally (needs Reader on the resource group):
```powershell
$env:IMAGE_TAG = '<a tag that exists in ACR>'
az deployment group what-if -g rg-platform-services -f infra/main.bicep -p infra/dev.bicepparam
```

## Platform contract
The shared pipeline relies on these; keep them in place:
- `Dockerfile` at the repo root, listening on port 8080, with `GET /health` returning 200.
- Maven wrapper (`mvnw`) and `pom.xml` at the root.
- `infra/main.bicep` plus `infra/dev.bicepparam` and `infra/qa.bicepparam`, reading `IMAGE_TAG`.
- `infra/modules/` is copied from `sampgreenwell-cyber/platform-bicep-modules`; update it from there.
