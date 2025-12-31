# OMIS Product Configurator CI/CD Options Plan

## 1. Objectives
- Turn the manual workflow in `DEPLOYMENT_WORKFLOW.md` into an auditable, low-touch pipeline.
- Ensure backend (`backend/`), frontend (`frontend/`), and CSV-to-MDB (`csv-to-mdb/`) services are tested, containerized, and published consistently.
- Support the current Azure VM footprint **and** keep a glidepath to Kubernetes by reusing `k8s-dev` GitOps patterns once AKS is provisioned.
- Automatically pull fresh images from the registry and roll workloads forward with zero SSH/manual Docker pulls.
- Reuse existing artifacts where possible (`deployToAzure/product-configurator-kubernetes`, `infra/k8s-dev`, Terraform modules) to reduce net-new YAML authoring.

## 2. Current State Summary
| Area | Observation |
| --- | --- |
| Infrastructure | Terraform in this repo stands up VM + Azure Container Registry (ACR) + DB. AKS manifests and Helm chart live in `/home/ishmamiqbal/Engineering/omis/product-configurator/deployToAzure`. Dev cluster GitOps example lives in `/home/ishmamiqbal/Engineering/infra/k8s-dev`. |
| Build | Engineers run `docker build`/`docker push` manually per service (see `DEPLOYMENT_WORKFLOW.md`, `deployToAzure/scripts/3-build-and-push-images.sh`). No shared pipeline for lint/test/build. |
| Deploy | Production currently uses docker-compose on a VM (`/opt/omis-pc`). Dev GitOps with ArgoCD (DigitalOcean) exists but Azure has no Kubernetes footprint yet. |
| Image Refresh | Manual `docker pull` + `docker compose up --force-recreate`. No controller watching ACR. |
| Secrets/Config | `.env` on VM; Helm values under `deployToAzure/product-configurator-kubernetes/environments`. |

## 3. Baseline Requirements for Any Option
1. **Source of Truth** – GitHub repo `omis/product-configurator` remains canonical for code; infra repos hold Terraform/Helm definitions.
2. **Build Steps** – Node 20 + Yarn tests/lint for backend/frontend; Maven build/tests for csv-to-mdb; Docker build contexts rooted per service.
3. **Artifact Registry** – Continue using `omispcacrprod.azurecr.io/omis-pc/*`. Dev/staging registries can be additional ACRs or DOCR used in `k8s-dev`.
4. **Deploy Targets** – Primary: existing VM stack today; future: AKS workloads via Helm chart in `deployToAzure/product-configurator-kubernetes` once cluster exists.
5. **Auto Image Adoption** – Either GitOps controller (ArgoCD Image Updater/Flux) commits tag bumps or VM/ACI workloads watch the registry via webhook/daemon (Watchtower, Container Apps revisions, etc.).
6. **Observability Hooks** – Every option should surface build + deploy status back to GitHub/ADO checks.

## 4. Shared Building Blocks
- **Helm Chart** (`deployToAzure/product-configurator-kubernetes/`): Templatizes backend, frontend, csvtomdb deployments + ingress; will be reused once AKS lands.
- **k8s-dev GitOps Repo** (`/home/ishmamiqbal/Engineering/infra/k8s-dev`): Implements ArgoCD App-of-Apps, Image Updater, Sealed Secrets; serves as blueprint even though prod is not yet on Kubernetes.
- **Terraform Outputs** (`projects/omis-pc/production`): Provide VM + ACR connection details; future modules can emit AKS kubeconfig.
- **Scripts** (`deployToAzure/scripts/*.sh`): Encode Azure CLI, Helm, secret creation – can be converted to pipeline steps regardless of target runtime.

## 5. CI/CD Options

### Option A – GitHub Actions + GitOps (ArgoCD on AKS)
Although AKS is not provisioned today, we preserve this option because `infra/k8s-dev` already proves the pattern for lower environments and the Helm chart in `deployToAzure` is Kubernetes-first. Capturing it now keeps a north-star for when AKS is introduced.

**Flow**
1. Trigger: PR + `main` merge for each service inside `omis/product-configurator`.
2. Jobs: lint/test/build matrix (frontend/back/csvtomdb). Artifacts get Dockerized via reusable workflow using service-specific Dockerfiles.
3. Publish: Push images to `omispcacrprod.azurecr.io` with tags tied to git SHA + semantic version.
4. GitOps Update: Workflow opens PR against a dedicated GitOps repo (clone of `infra/k8s-dev` but tuned for Azure) updating image tags; ArgoCD Image Updater can also automate this push.
5. Deploy: ArgoCD syncs Helm release in AKS; Image Updater ensures workloads pull new tags. Rollbacks handled via git revert.
6. Drift detection/alerts handled by ArgoCD status + GitHub PR checks.

**High-Level Architecture:**
```
┌───────────────────────────────────────────────────────────────┐
│                GITHUB ACTIONS (CI/CD)                          │
│  Lint/Test  →  Build Images  →  Push to ACR                    │
└──────────────┬────────────────────────────────────────────────┘
               │ (publish)                                       
┌──────────────▼──────────────────────────────┐                  
│    AZURE CONTAINER REGISTRY (omispcacr)     │                  
└──────────────┬──────────────────────────────┘                  
               │ (new tag event)                                 
┌──────────────▼──────────────────────────────┐                  
│        GITOPS REPO (k8s-azure-prod)         │                  
│  Image Updater bumps Helm values            │                  
└──────────────┬──────────────────────────────┘                  
               │ (sync manifests)                               
┌──────────────▼──────────────────────────────┐                  
│             ARGOCD ON AKS (control)         │                  
│  Applies Helm chart → deploys workloads     │                  
└──────────────┬──────────────────────────────┘                  
               │ (desired state)                                 
┌──────────────▼──────────────────────────────┐                  
│                AKS NAMESPACES               │                  
│  FE / BE / csvtomdb Deployments pull ACR    │                  
└─────────────────────────────────────────────┘                  
```

**Detailed CI/CD Workflow (Step-by-Step):**
```
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: CODE CHANGE                                                 │
│ Developer pushes to main branch                                     │
│ ┌────────────────────────────────────────────────────┐              │
│ │ omis/product-configurator                          │              │
│ │  • frontend/ changes                               │              │
│ │  • backend/ changes                                │              │
│ │  • csv-to-mdb/ changes                             │              │
│ └────────────────────────────────────────────────────┘              │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│ STEP 2: GITHUB ACTIONS CI (Parallel Matrix Build)                   │
│                                                                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │ Frontend Job    │  │ Backend Job     │  │ csvtomdb Job     │    │
│  │ • Checkout      │  │ • Checkout      │  │ • Checkout       │    │
│  │ • Node 20       │  │ • Node 20       │  │ • Java 17        │    │
│  │ • yarn install  │  │ • yarn install  │  │ • mvn test       │    │
│  │ • yarn lint     │  │ • yarn lint     │  │ • mvn package    │    │
│  │ • yarn test     │  │ • yarn test     │  │ • Docker build   │    │
│  │ • yarn build    │  │ • yarn build    │  │ • Push to ACR    │    │
│  │ • Docker build  │  │ • Docker build  │  │                  │    │
│  │ • Push to ACR   │  │ • Push to ACR   │  │                  │    │
│  └────────┬────────┘  └────────┬────────┘  └────────┬─────────┘    │
│           │                    │                     │              │
│           └────────────────────┴─────────────────────┘              │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ (all 3 images pushed)
┌─────────────────────────────────▼───────────────────────────────────┐
│ STEP 3: AZURE CONTAINER REGISTRY                                    │
│                                                                      │
│  omispcacrprod.azurecr.io/omis-pc/                                  │
│   ├── frontend:abc123def (git SHA)                                  │
│   ├── frontend:latest                                               │
│   ├── backend:abc123def                                             │
│   ├── backend:latest                                                │
│   ├── csvtomdb:abc123def                                            │
│   └── csvtomdb:latest                                               │
│                                                                      │
│  ACR webhook → triggers ArgoCD Image Updater                        │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ (Image Updater detects new tags)
┌─────────────────────────────────▼───────────────────────────────────┐
│ STEP 4: ARGOCD IMAGE UPDATER (Automated GitOps Update)              │
│                                                                      │
│  ┌──────────────────────────────────────────────────────┐           │
│  │ ArgoCD Image Updater polls ACR every 2 minutes       │           │
│  │ • Finds: frontend:abc123def (new)                    │           │
│  │ • Compares with current: frontend:xyz789abc (old)    │           │
│  │ • Updates GitOps repo: k8s-azure-prod                │           │
│  └────────────────────────┬─────────────────────────────┘           │
│                           │                                         │
│                           ▼                                         │
│  ┌──────────────────────────────────────────────────────┐           │
│  │ Git commit to k8s-azure-prod/values-prod.yaml        │           │
│  │                                                       │           │
│  │  frontend:                                            │           │
│  │    image:                                             │           │
│  │ -    tag: xyz789abc  # old                           │           │
│  │ +    tag: abc123def  # new                           │           │
│  │                                                       │           │
│  │  backend:                                             │           │
│  │    image:                                             │           │
│  │ -    tag: old456ghi                                  │           │
│  │ +    tag: abc123def                                  │           │
│  └──────────────────────────────────────────────────────┘           │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ (GitOps repo updated)
┌─────────────────────────────────▼───────────────────────────────────┐
│ STEP 5: ARGOCD SYNC (Declarative Deployment)                        │
│                                                                      │
│  ┌──────────────────────────────────────────────────────┐           │
│  │ ArgoCD detects Git repo change                       │           │
│  │ • Compares desired state (Git) vs actual (AKS)       │           │
│  │ • Calculates diff                                    │           │
│  │ • Syncs automatically (or manual approval)           │           │
│  └────────────────────────┬─────────────────────────────┘           │
│                           │                                         │
│                           ▼                                         │
│  ┌──────────────────────────────────────────────────────┐           │
│  │ kubectl apply via ArgoCD                             │           │
│  │ • Rolling update: frontend Deployment                │           │
│  │ • Rolling update: backend Deployment                 │           │
│  │ • Rolling update: csvtomdb Deployment                │           │
│  │                                                       │           │
│  │ Health checks:                                        │           │
│  │ ✓ Readiness probes pass                              │           │
│  │ ✓ Liveness probes healthy                            │           │
│  │ ✓ Old pods terminated gracefully                     │           │
│  └──────────────────────────────────────────────────────┘           │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ (deployment complete)
┌─────────────────────────────────▼───────────────────────────────────┐
│ STEP 6: PRODUCTION AKS CLUSTER (Running State)                      │
│                                                                      │
│  ┌────────────────────────────────────────────────┐                 │
│  │ Ingress Controller (nginx/traefik)             │                 │
│  │  • HTTPS endpoint: https://omis-pc.example.com │                 │
│  │  • TLS certificate (Let's Encrypt / cert-mgr)  │                 │
│  └─────────────────┬──────────────────────────────┘                 │
│                    │                                                │
│  ┌─────────────────▼────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Frontend Pods (2 replica)│  │ Backend Pods │  │ csvtomdb Pod │  │
│  │ • frontend:abc123def     │  │ • backend... │  │ • csvtomdb.. │  │
│  │ • Pulls from ACR         │  │              │  │              │  │
│  │ • Serves Next.js app     │  │              │  │              │  │
│  └──────────────────────────┘  └──────────────┘  └──────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────┐                   │
│  │ PostgreSQL (Azure Database)                  │                   │
│  │ • Connected via Service                      │                   │
│  └──────────────────────────────────────────────┘                   │
└──────────────────────────────────────────────────────────────────────┘
```

**Rollback Process (Git-Based):**
```
┌────────────────────────────────────────────────────────┐
│ ROLLBACK SCENARIO: Bad deployment detected            │
└────────────────────┬───────────────────────────────────┘
                     │
┌────────────────────▼──────────────────────────────────┐
│ Developer runs: git revert <commit-hash>               │
│ (in k8s-azure-prod GitOps repo)                        │
│                                                         │
│  values-prod.yaml:                                      │
│  frontend:                                              │
│    tag: abc123def  ← BAD (causes errors)               │
│                                                         │
│  Revert to:                                             │
│  frontend:                                              │
│    tag: xyz789abc  ← GOOD (last known working)         │
└────────────────────┬───────────────────────────────────┘
                     │ (git push)
┌────────────────────▼───────────────────────────────────┐
│ ArgoCD detects Git change                              │
│ • Syncs automatically                                  │
│ • Rolls pods back to previous image                    │
│ • No manual kubectl commands needed                    │
└─────────────────────────────────────────────────────────┘

Time to rollback: ~2 minutes (ArgoCD sync interval)
Audit trail: Git commit history shows who/when/why
```

**Pros**
- Mirrors existing dev GitOps pattern; high confidence due to `k8s-dev` reference implementation.
- Native auto image updates via ArgoCD Image Updater ensures pods always pull latest tags without scripting inside AKS.
- Easy promotion workflows (dev → staging → prod) by merging GitOps PRs per environment.
- Works even if AKS cluster is rebuilt—state lives in Git.

**Cons / Considerations**
- Requires AKS cluster + ArgoCD/cert-manager installation that does not exist yet.
- Developers must manage two PRs (app repo + GitOps repo) unless auto-PR step is streamlined.
- Secret management must switch from `.env` to Sealed Secrets/k8s secrets; need bootstrap.

**Implementation Tasks**
- [ ] Provision AKS + supporting services via Terraform module or `deployToAzure/scripts`.
- [ ] Clone `infra/k8s-dev` into e.g. `infra/k8s-azure-prod`, replace DO-specific bits with Azure load balancer + `omispcacrprod` registry secret.
- [ ] Add GitHub Actions workflows (`.github/workflows/ci.yml`, `cd.yml`) that run tests, build multi-arch images, push to ACR, and modify Helm values (use `azure/login`, `azure/acr` actions).
- [ ] Configure ArgoCD Image Updater to talk to ACR (PAT or managed identity) so it bumps tags when new images appear, preserving "automatically pulled from registry" requirement.
- [ ] Wire GitHub checks to block merges if CI fails; optional manual approvals for prod deploy by gating ArgoCD sync via PR merge.

### Option B – Azure DevOps Pipelines + GitOps Hand-off
**Flow**
1. Use Azure Repos or mirror GitHub repo into Azure DevOps project. Build pipeline handles lint/test/build for all services.
2. Pipeline stages: Build & test → Containerize & push to ACR → GitOps PR update.
3. Multi-stage YAML pipeline enforces approvals between staging/prod and can store secrets in Azure Key Vault.
4. Deploy state managed by ArgoCD GitOps repo (same as Option A) or by Azure GitOps extension.

**High-Level Architecture:**
```
┌───────────────────────────────────────────────────────────────┐
│              AZURE DEVOPS MULTI-STAGE PIPELINE                 │
│  CI Stage → Build Images → Push to ACR → Create GitOps PR      │
└──────────────┬────────────────────────────────────────────────┘
               │ (service connection)                            
┌──────────────▼──────────────────────────────┐                  
│    AZURE CONTAINER REGISTRY (omispcacr)     │                  
└──────────────┬──────────────────────────────┘                  
               │ (tag metadata)                                  
┌──────────────▼──────────────────────────────┐                  
│        GITOPS REPO / FLUX CONFIG            │                  
│  PR merges update Helm values               │                  
└──────────────┬──────────────────────────────┘                  
               │ (sync)                                          
┌──────────────▼──────────────────────────────┐                  
│ ArgoCD / Flux Controller running on AKS     │                  
│  Applies manifests to AKS namespaces        │                  
└─────────────────────────────────────────────┘                  
```

**Detailed Multi-Stage Pipeline Workflow:**
```
┌──────────────────────────────────────────────────────────────────┐
│ AZURE DEVOPS PIPELINE: azure-pipelines.yml                       │
│                                                                   │
│  trigger:                                                         │
│    branches: [main]                                              │
│  pool:                                                            │
│    vmImage: 'ubuntu-latest'                                      │
└──────────────────────┬───────────────────────────────────────────┘
                       │
┌──────────────────────▼────────────────────────────────────────────┐
│ STAGE 1: BUILD & TEST (Parallel Jobs)                             │
│                                                                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐│
│  │ Job: Frontend    │  │ Job: Backend     │  │ Job: csvtomdb    ││
│  │                  │  │                  │  │                  ││
│  │ Steps:           │  │ Steps:           │  │ Steps:           ││
│  │ 1. Checkout      │  │ 1. Checkout      │  │ 1. Checkout      ││
│  │ 2. Node 20 setup │  │ 2. Node 20 setup │  │ 2. Java 17 setup ││
│  │ 3. Cache restore │  │ 3. Cache restore │  │ 3. Maven cache   ││
│  │ 4. yarn install  │  │ 4. yarn install  │  │ 4. mvn clean     ││
│  │ 5. yarn lint     │  │ 5. yarn lint     │  │ 5. mvn test      ││
│  │ 6. yarn test     │  │ 6. yarn test     │  │ 6. mvn package   ││
│  │    - coverage    │  │    - coverage    │  │                  ││
│  │ 7. Publish tests │  │ 7. Publish tests │  │ 7. Publish tests ││
│  │ 8. Cache save    │  │ 8. Cache save    │  │                  ││
│  └──────────────────┘  └──────────────────┘  └──────────────────┘│
│                                                                    │
│  Gate: All tests must pass ✓                                      │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ (tests passed)
┌──────────────────────▼─────────────────────────────────────────────┐
│ STAGE 2: CONTAINERIZE & PUSH (ACR Integration)                     │
│                                                                     │
│  Service Connection: omispcacrprod (Managed Identity)              │
│                                                                     │
│  Steps:                                                             │
│  1. Azure CLI login (service connection)                           │
│  2. ACR login (az acr login --name omispcacrprod)                  │
│  3. Build frontend image:                                          │
│     docker build -t omispcacrprod.azurecr.io/omis-pc/frontend:$TAG │
│  4. Build backend image:                                           │
│     docker build -t omispcacrprod.azurecr.io/omis-pc/backend:$TAG  │
│  5. Build csvtomdb image:                                          │
│     docker build -t omispcacrprod.azurecr.io/omis-pc/csvtomdb:$TAG │
│  6. Push all images to ACR                                         │
│  7. Tag images as :latest                                          │
│  8. Push :latest tags                                              │
│                                                                     │
│  Variables:                                                         │
│  - TAG=$(Build.SourceVersion) # Git SHA                            │
│  - SEMANTIC_VERSION=$(GitVersion.SemVer) # e.g., 1.2.3             │
│                                                                     │
│  Outputs:                                                           │
│  - Image digests published to pipeline artifacts                   │
└──────────────────────┬────────────────────────────────────────────┘
                       │ (images in ACR)
┌──────────────────────▼─────────────────────────────────────────────┐
│ STAGE 3: UPDATE GITOPS (Staging Environment)                       │
│                                                                     │
│  Deployment: UpdateGitOps-Staging                                  │
│  Environment: omis-pc-staging (auto-approve)                       │
│                                                                     │
│  Steps:                                                             │
│  1. Checkout GitOps repo (k8s-azure-staging)                       │
│  2. Install yq (YAML processor)                                    │
│  3. Update values-staging.yaml:                                    │
│     yq -i '.frontend.image.tag = "$TAG"' values-staging.yaml       │
│     yq -i '.backend.image.tag = "$TAG"' values-staging.yaml        │
│     yq -i '.csvtomdb.image.tag = "$TAG"' values-staging.yaml       │
│  4. Git commit changes:                                            │
│     git commit -m "chore: update staging to $TAG"                  │
│  5. Git push to GitOps repo                                        │
│                                                                     │
│  Flux/ArgoCD detects change and syncs to AKS staging namespace     │
└──────────────────────┬────────────────────────────────────────────┘
                       │ (staging deployed, running tests)
┌──────────────────────▼─────────────────────────────────────────────┐
│ STAGE 4: APPROVAL GATE (Manual Intervention)                       │
│                                                                     │
│  ┌────────────────────────────────────────────────────┐            │
│  │ Environment: omis-pc-production                    │            │
│  │ Approvers: [DevOps Team, Product Owner]            │            │
│  │                                                     │            │
│  │ Pre-deployment checks:                              │            │
│  │ ✓ Staging smoke tests passed                       │            │
│  │ ✓ No active incidents                              │            │
│  │ ✓ Change window: weekdays 10am-4pm EST             │            │
│  │                                                     │            │
│  │ Approval options:                                   │            │
│  │ [Approve] [Reject] [Defer]                         │            │
│  │                                                     │            │
│  │ Approval timeout: 7 days                            │            │
│  │ Notifications: Email, Teams, ServiceNow             │            │
│  └────────────────────────────────────────────────────┘            │
└──────────────────────┬────────────────────────────────────────────┘
                       │ (approved)
┌──────────────────────▼─────────────────────────────────────────────┐
│ STAGE 5: PRODUCTION DEPLOYMENT (GitOps Update)                     │
│                                                                     │
│  Deployment: UpdateGitOps-Production                               │
│  Environment: omis-pc-production (approval required ✓)             │
│                                                                     │
│  Steps:                                                             │
│  1. Fetch secrets from Azure Key Vault:                            │
│     - Database connection string                                   │
│     - API keys (SendGrid, etc.)                                    │
│     - Certificates                                                 │
│  2. Checkout GitOps repo (k8s-azure-prod)                          │
│  3. Create PR to update values-prod.yaml:                          │
│     - New image tags                                               │
│     - Change description                                           │
│     - Link to build                                                │
│  4. Auto-merge PR (or require GitOps approval)                     │
│  5. Wait for ArgoCD/Flux to sync (poll for health)                 │
│  6. Run production smoke tests:                                    │
│     - Health endpoints (/api/health)                               │
│     - Database connectivity                                        │
│     - Frontend loads                                               │
│  7. Publish deployment event to ServiceNow/PagerDuty               │
└──────────────────────┬────────────────────────────────────────────┘
                       │ (production live)
┌──────────────────────▼─────────────────────────────────────────────┐
│ STAGE 6: POST-DEPLOYMENT (Monitoring & Alerts)                     │
│                                                                     │
│  Steps:                                                             │
│  1. Create Azure Monitor query for errors (10 min window)          │
│  2. Check Application Insights for exceptions                      │
│  3. Verify Prometheus metrics:                                     │
│     - HTTP 5xx errors < 1%                                         │
│     - Response time p95 < 500ms                                    │
│     - Pod restart count = 0                                        │
│  4. Send deployment notification:                                  │
│     Teams: "✅ v1.2.3 deployed to production"                      │
│     Slack: "#deployments channel"                                  │
│  5. Create deployment tag in Git                                   │
│  6. Update CHANGELOG.md (optional)                                 │
│                                                                     │
│  Auto-rollback conditions:                                         │
│  - If error rate > 5% within 10 minutes → trigger rollback pipeline│
│  - If health checks fail → rollback                                │
└─────────────────────────────────────────────────────────────────────┘
```

**Azure DevOps Dashboard View:**
```
┌──────────────────────────────────────────────────────────────┐
│ AZURE DEVOPS PIPELINES DASHBOARD                             │
│                                                               │
│  Pipeline: omis-pc-deploy                                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Run #142  main (abc123d)  "feat: add export feature"   │  │
│  │ Triggered by: johndoe@omis.com                          │  │
│  │ Duration: 12m 34s                                       │  │
│  │                                                          │  │
│  │ ✓ Build & Test          3m 21s   Passed                │  │
│  │ ✓ Containerize & Push   4m 12s   Passed                │  │
│  │ ✓ Deploy Staging        2m 45s   Passed                │  │
│  │ ⏸ Approval Gate          -       Pending (Jane Doe)    │  │
│  │ ⏳ Deploy Production      -       Waiting...            │  │
│  │ ⏳ Post-Deployment        -       Waiting...            │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Test Results:                                               │
│  ✓ Frontend: 87 tests passed                                │
│  ✓ Backend: 124 tests passed                                │
│  ✓ csvtomdb: 43 tests passed                                │
│  Code Coverage: 78% (target: 75%)                            │
│                                                               │
│  Published Artifacts:                                        │
│  📦 frontend:abc123d (142 MB)                                │
│  📦 backend:abc123d (98 MB)                                  │
│  📦 csvtomdb:abc123d (234 MB)                                │
└──────────────────────────────────────────────────────────────┘
```

**Integration with Azure Services:**
```
┌───────────────────────────────────────────────────────────┐
│ AZURE DEVOPS INTEGRATIONS                                 │
│                                                            │
│  ┌─────────────────────────────────────┐                  │
│  │ Azure Key Vault                     │                  │
│  │ • DB passwords (refreshed daily)    │                  │
│  │ • API keys                          │                  │
│  │ • Certificates                      │                  │
│  │                                     │                  │
│  │ Access via: Managed Identity        │                  │
│  │ No secrets in pipeline YAML ✓       │                  │
│  └─────────────────┬───────────────────┘                  │
│                    │                                       │
│  ┌─────────────────▼───────────────────┐                  │
│  │ Azure Monitor / App Insights        │                  │
│  │ • Pipeline logs ingested            │                  │
│  │ • Deployment annotations            │                  │
│  │ • Performance baselines             │                  │
│  └─────────────────┬───────────────────┘                  │
│                    │                                       │
│  ┌─────────────────▼───────────────────┐                  │
│  │ Azure Boards (Work Items)           │                  │
│  │ • Auto-link commits to stories      │                  │
│  │ • Deployment status updates         │                  │
│  │ • Release notes generation          │                  │
│  └─────────────────┬───────────────────┘                  │
│                    │                                       │
│  ┌─────────────────▼───────────────────┐                  │
│  │ Azure Repos (Git)                   │                  │
│  │ • Branch policies enforced          │                  │
│  │ • PR builds required                │                  │
│  │ • Code reviewers                    │                  │
│  └─────────────────────────────────────┘                  │
└───────────────────────────────────────────────────────────┘
```

**Pros**
- Tight integration with Azure subscriptions, Managed Identity for ACR/AKS, Key Vault integration for secrets (no PATs).
- Built-in environment approvals, deployment dashboards, audit logs.
- Allows parallel adoption of Azure DevOps for other OMIS services.

**Cons / Considerations**
- Additional platform operational overhead (licensing/users) versus GitHub-only workflows.
- Need service connections to GitHub or code migration into Azure Repos.
- Still need to maintain GitOps repo/ArgoCD unless pivoting entirely to Azure GitOps extension (Flux).

**Implementation Tasks**
- [ ] Create Azure DevOps project; set up service connections to AKS + ACR + GitHub.
- [ ] Author `azure-pipelines.yml` with stages (CI/test → Build images → Update GitOps repo or run `kubectl` apply).
- [ ] Integrate Key Vault task to fetch secrets for build-time (Sendgrid keys, etc.).
- [ ] Optionally replace ArgoCD with Flux via Azure GitOps extension for native image automation while keeping Helm chart from `deployToAzure/product-configurator-kubernetes`.

### Option C – GitHub Actions Direct-to-AKS (no GitOps)
**Flow**
1. GitHub Actions pipeline builds/tests/pushes images (same as Option A).
2. Deployment job logs into AKS using `azure/aks-set-context` and runs Helm upgrade against `deployToAzure/product-configurator-kubernetes` chart directly from the repo.
3. Automatic image refresh achieved via `az acr webhook` triggering a Function/Webhook that runs `kubectl rollout restart` or by running Watchtower-like controller inside cluster to monitor `Deployment` image tags.

**High-Level Architecture:**
```
┌───────────────────────────────────────────────────────────────┐
│                GITHUB ACTIONS (CI/CD)                          │
│  Tests → Build → Push to ACR → Helm Upgrade step               │
└──────────────┬────────────────────────────────────────────────┘
               │ (publish & deploy)                              
┌──────────────▼──────────────────────────────┐                  
│    AZURE CONTAINER REGISTRY (omispcacr)     │                  
└──────────────┬──────────────────────────────┘                  
               │ (image references)                              
┌──────────────▼──────────────────────────────┐                  
│  GHA Deployment Job w/ AKS Credentials      │                  
│  Runs Helm upgrade using repo chart         │                  
└──────────────┬──────────────────────────────┘                  
               │ (apply manifests)                               
┌──────────────▼──────────────────────────────┐                  
│             AKS CLUSTER (workloads)         │                  
│  Deployments pull latest tags from ACR      │                  
└─────────────────────────────────────────────┘                  
```

**Detailed Direct Deployment Workflow:**
```
┌────────────────────────────────────────────────────────────────┐
│ STEP 1: GITHUB ACTIONS CI (Build & Test)                       │
│ (Same as Option A - see above for details)                     │
│                                                                 │
│  ✓ Lint → Test → Build → Push to ACR                          │
│  Result: Images in omispcacrprod.azurecr.io/omis-pc/*          │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│ STEP 2: DEPLOY JOB (Direct Helm Deployment)                    │
│                                                                 │
│  Job: deploy-to-aks                                             │
│  Runs-on: ubuntu-latest                                        │
│  Environment: production  # GitHub Environment protection       │
│                                                                 │
│  Steps:                                                         │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 1. Azure Login (OIDC - no static secrets)           │      │
│  │    uses: azure/login@v1                              │      │
│  │    with:                                              │      │
│  │      client-id: ${{ secrets.AZURE_CLIENT_ID }}       │      │
│  │      tenant-id: ${{ secrets.AZURE_TENANT_ID }}       │      │
│  │      subscription-id: ${{ secrets.AZURE_SUB_ID }}    │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 2. Set AKS Context                                   │      │
│  │    uses: azure/aks-set-context@v3                    │      │
│  │    with:                                              │      │
│  │      resource-group: sazim-3dif-omis-pc-prod         │      │
│  │      cluster-name: omis-pc-aks-prod                  │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 3. Install Helm                                      │      │
│  │    uses: azure/setup-helm@v3                         │      │
│  │    with:                                              │      │
│  │      version: '3.12.0'                               │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 4. Deploy Helm Chart                                 │      │
│  │    run: |                                             │      │
│  │      helm upgrade --install omis-pc \                │      │
│  │        ./deployToAzure/product-configurator-k8s/ \   │      │
│  │        --namespace production \                       │      │
│  │        --create-namespace \                           │      │
│  │        --set frontend.image.tag=${{ github.sha }} \  │      │
│  │        --set backend.image.tag=${{ github.sha }} \   │      │
│  │        --set csvtomdb.image.tag=${{ github.sha }} \  │      │
│  │        --set ingress.host=omis-pc.example.com \      │      │
│  │        --wait --timeout 5m                            │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 5. Verify Deployment                                 │      │
│  │    run: |                                             │      │
│  │      kubectl rollout status deployment/frontend \    │      │
│  │        -n production --timeout=5m                     │      │
│  │      kubectl rollout status deployment/backend \     │      │
│  │        -n production --timeout=5m                     │      │
│  │      kubectl rollout status deployment/csvtomdb \    │      │
│  │        -n production --timeout=5m                     │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ 6. Health Check                                      │      │
│  │    run: |                                             │      │
│  │      sleep 30  # Wait for pods to stabilize          │      │
│  │      curl -f https://omis-pc.example.com/api/health  │      │
│  │      curl -f https://omis-pc.example.com/            │      │
│  └──────────────────────────────────────────────────────┘      │
└────────────────────────────┬────────────────────────────────────┘
                             │ (deployment complete)
┌────────────────────────────▼────────────────────────────────────┐
│ STEP 3: PRODUCTION AKS CLUSTER (Running State)                  │
│                                                                  │
│  Namespace: production                                          │
│                                                                  │
│  ┌───────────────────────────────────────────────┐              │
│  │ Helm Release: omis-pc (revision 42)           │              │
│  │ Status: deployed                               │              │
│  │ Last Updated: 2026-01-02 12:45:23 UTC         │              │
│  └───────────────────────────────────────────────┘              │
│                                                                  │
│  Resources:                                                     │
│  • Deployment/frontend (2 replicas) - frontend:abc123d         │
│  • Deployment/backend (2 replicas) - backend:abc123d           │
│  • Deployment/csvtomdb (1 replica) - csvtomdb:abc123d          │
│  • Service/frontend-svc (ClusterIP)                             │
│  • Service/backend-svc (ClusterIP)                              │
│  • Ingress/omis-pc-ingress (nginx)                              │
│  • Secret/db-credentials                                        │
│  • ConfigMap/app-config                                         │
└──────────────────────────────────────────────────────────────────┘
```

**Comparison: Direct Deploy vs GitOps**
```
┌────────────────────────────────────────────────────────────────┐
│ CHARACTERISTIC      │ OPTION C (Direct)  │ OPTION A (GitOps)  │
├─────────────────────┼────────────────────┼────────────────────┤
│ Deployment Trigger  │ GitHub Workflow    │ Git Commit         │
│ State Storage       │ AKS Cluster        │ Git Repository     │
│ Rollback Method     │ helm rollback      │ git revert         │
│ Audit Trail         │ GitHub Actions log │ Git history        │
│ Drift Detection     │ None (manual)      │ Automatic (ArgoCD) │
│ Multi-Cluster Sync  │ Manual (N scripts) │ Auto (ArgoCD Apps) │
│ Secrets in Repo     │ GitHub Secrets     │ Sealed Secrets     │
│ Complexity          │ Low                │ Medium             │
│ Setup Time          │ 1-2 days           │ 1-2 weeks          │
│ Best For            │ Single cluster     │ Multi-env/Multi-AKS│
└────────────────────────────────────────────────────────────────┘
```

**Automatic Image Updates (ACR Webhook Approach):**
```
┌────────────────────────────────────────────────────────────────┐
│ ALTERNATIVE: ACR WEBHOOK + AZURE FUNCTION                      │
│                                                                 │
│  Problem: GitHub Actions only runs on code push                │
│  Need: Auto-deploy when image is rebuilt (e.g., security patch)│
│                                                                 │
│  Solution Flow:                                                 │
│  ┌──────────────────────────────────────────┐                  │
│  │ 1. ACR Webhook Configuration             │                  │
│  │    Event: image push                     │                  │
│  │    Scope: omis-pc/*:latest               │                  │
│  │    Target: Azure Function HTTP endpoint  │                  │
│  └──────────────┬───────────────────────────┘                  │
│                 │                                               │
│  ┌──────────────▼───────────────────────────┐                  │
│  │ 2. Azure Function (Node.js/Python)       │                  │
│  │    Triggered when new image pushed       │                  │
│  │                                           │                  │
│  │    async function handler(event) {       │                  │
│  │      const imageName = event.target.name │                  │
│  │      const tag = event.target.tag        │                  │
│  │                                           │                  │
│  │      // Authenticate to AKS              │                  │
│  │      await execShellCommand(             │                  │
│  │        'az aks get-credentials ...'      │                  │
│  │      )                                    │                  │
│  │                                           │                  │
│  │      // Rolling restart deployment       │                  │
│  │      await kubectl(                      │                  │
│  │        `rollout restart deployment/      │                  │
│  │         ${imageName} -n production`      │                  │
│  │      )                                    │                  │
│  │                                           │                  │
│  │      return { status: 'restarted' }      │                  │
│  │    }                                      │                  │
│  └──────────────┬───────────────────────────┘                  │
│                 │                                               │
│  ┌──────────────▼───────────────────────────┐                  │
│  │ 3. AKS Cluster                           │                  │
│  │    • Pods restarted with imagePullPolicy:│                  │
│  │      Always                               │                  │
│  │    • Pulls fresh image from ACR          │                  │
│  │    • Rolling update (zero downtime)      │                  │
│  └──────────────────────────────────────────┘                  │
│                                                                 │
│  Setup Commands:                                                │
│  az acr webhook create \                                        │
│    --name omispcWebhook \                                       │
│    --registry omispcacrprod \                                   │
│    --uri https://omis-pc-updater.azurewebsites.net/webhook \   │
│    --actions push \                                             │
│    --scope omis-pc/*:latest                                     │
└─────────────────────────────────────────────────────────────────┘
```

**Rollback Process (Helm-Based):**
```
┌────────────────────────────────────────────────────────┐
│ ROLLBACK SCENARIO: Deployment failed health checks     │
└────────────────────┬───────────────────────────────────┘
                     │
┌────────────────────▼───────────────────────────────────┐
│ Option 1: Manual Rollback (via kubectl)                │
│                                                         │
│  $ kubectl get pods -n production                       │
│  NAME                        READY   STATUS             │
│  frontend-7d8f9c-xyz         0/1     CrashLoopBackOff  │
│  frontend-7d8f9c-abc         0/1     CrashLoopBackOff  │
│                                                         │
│  $ helm rollback omis-pc -n production                 │
│  Rollback was a success! Happy Helming!                │
│                                                         │
│  # OR specify revision number:                          │
│  $ helm rollback omis-pc 41 -n production              │
│  (Rolls back to revision 41)                            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Option 2: Automated Rollback (GitHub Actions)           │
│                                                          │
│  Workflow: .github/workflows/rollback.yml               │
│  Trigger: workflow_dispatch (manual)                    │
│                                                          │
│  Inputs:                                                 │
│  - revision: "41" (Helm revision number)                │
│  - reason: "Frontend crashing due to API change"        │
│                                                          │
│  Steps:                                                  │
│  1. Login to Azure                                      │
│  2. Set AKS context                                     │
│  3. helm rollback omis-pc ${{ inputs.revision }}        │
│  4. Verify rollback success                             │
│  5. Create incident ticket                              │
│  6. Notify team (Slack/email)                           │
└─────────────────────────────────────────────────────────┘

Rollback Time: ~2 minutes (Helm rollback + pod restart)
Audit Trail: Helm history + GitHub Actions log
Risk: No declarative state; cluster is source of truth
```

**Pros**
- Simplest to reason about once AKS exists; single repo and single workflow.
- No separate GitOps repo; release defined by workflow run.
- Can keep existing docker-compose VM deployment as fallback while AKS matures.

**Cons / Considerations**
- Less auditable; cluster drift possible because desired state not stored in Git separately.
- Need to store kubeconfig/credentials in GitHub secrets. Rotations become manual.
- Auto image updates rely on custom webhook/controller rather than GitOps image updater.

**Implementation Tasks**
- [ ] Harden GitHub secrets (AKS kubeconfig, ACR creds, DB passwords) using OIDC to avoid static secrets.
- [ ] Write deployment scripts inside workflow referencing `deployToAzure/scripts/5-deploy-application.sh` logic.
- [ ] Deploy Watchtower or KEDA-based job to detect new tags and restart pods, or rely entirely on `helm upgrade --set image.tag=$NEW_TAG` per workflow run.

### Option D – Transitional VM Automation (Caddy + Watchtower + GitHub Actions)

**Current Infrastructure State:**
The VM is already deployed with:
- ✅ **Caddy reverse proxy** (automatic HTTPS when domain is configured)
- ✅ **Docker Compose** running frontend, backend, csvtomdb services
- ✅ **NSG rules** allowing ports 80, 443, 3000, 5000, 5001
- ✅ **Azure Container Registry** (ACR) provisioned
- ⚠️ **No automatic image updates** (manual pull & restart required)
- ⚠️ **No CI/CD pipeline** connected to production VM

**Flow diagram (current architecture):**
```
┌───────────────────────────────────────────────────────────────┐
│                  GITHUB ACTIONS (CI)                           │
│  Lint/Test  →  Build Images  →  Push to ACR                    │
└──────────────┬────────────────────────────────────────────────┘
               │ (new tags published)                            
┌──────────────▼──────────────────────────────┐                  
│       AZURE CONTAINER REGISTRY (ACR)        │                  
│       omispcacrprod.azurecr.io              │                  
└──────────────┬──────────────────────────────┘                  
               │ (manual pull OR Watchtower polls)               
┌──────────────▼──────────────────────────────┐                  
│            PROD VM / docker-compose         │                  
│  ┌─────────────────────────────────────┐    │                  
│  │ Caddy (Reverse Proxy + Auto HTTPS)  │    │                  
│  │  - Port 80/443 → Services           │    │                  
│  │  - Let's Encrypt certificates       │    │                  
│  │  - HTTP→HTTPS redirect              │    │                  
│  └─────────────────────────────────────┘    │                  
│  ┌─────────────────────────────────────┐    │                  
│  │ Application Services                │    │                  
│  │  - frontend:3000                    │    │                  
│  │  - backend:5000/5001                │    │                  
│  │  - csvtomdb:8080                    │    │                  
│  └─────────────────────────────────────┘    │                  
│  ┌─────────────────────────────────────┐    │                  
│  │ Watchtower (OPTIONAL - not deployed)│    │                  
│  │  - Polls ACR for updates            │    │                  
│  │  - Auto-pulls & restarts containers │    │                  
│  └─────────────────────────────────────┘    │                  
└─────────────────────────────────────────────┘                  
```

**What's Already Working:**
1. ✅ GitHub Actions builds/tests each service (backend has `reusable-deploy.yml`, `deploy-staging-dev.yml`)
2. ✅ Images can be pushed to ACR manually
3. ✅ Caddy proxies all traffic and handles HTTPS when domain is configured
4. ✅ Services run via docker-compose

**What's Missing:**
1. ❌ Automated production deployment workflow (GitHub Actions → ACR → VM)
2. ❌ Automatic image updates on VM (Watchtower or equivalent)
3. ❌ Health checks after deployment
4. ❌ Rollback mechanism
5. ❌ Deployment notifications

---

**Pros**
- Minimal change to current production footprint while AKS work is in-flight
- Automatically satisfies "builds are pulled from registry and updated" (when Watchtower added)
- No Kubernetes dependency; leverages existing VM infrastructure
- **Caddy already provides production-ready HTTPS** when domain is configured
- Existing GitHub Actions workflows can be adapted for Azure

**Cons / Considerations**
- Still tied to single VM SPOF; no GitOps benefits
- Watchtower credentials to ACR must be managed securely
- Lacks deployment history unless `docker compose` logs are aggregated elsewhere
- Caddy configuration changes require container restart
- No blue/green or canary deployments

---

**Implementation Tasks**

#### Phase 1: Adapt Existing Workflows for Azure (Immediate)
- [ ] Review existing `omis/product-configurator/backend/.github/workflows/reusable-deploy.yml`
- [ ] Create production workflow `.github/workflows/deploy-prod-azure.yml` that:
  - Triggers on: push to `main` branch (or manual trigger)
  - Builds all 3 services (frontend, backend, csvtomdb)
  - Tags images with git SHA + `latest`
  - Pushes to `omispcacrprod.azurecr.io/omis-pc/*`
  - Uses Azure login action: `azure/login@v1`
  - Uses ACR login: `az acr login --name omispcacrprod`
- [ ] Set up GitHub Secrets:
  - `AZURE_CREDENTIALS` - Service principal with ACR push access
  - `ACR_LOGIN_SERVER` - `omispcacrprod.azurecr.io`
  - (Database credentials, API keys already in VM `.env`, not in GitHub)
- [ ] Test workflow by triggering manual deployment

**Example workflow structure:**
```yaml
# .github/workflows/deploy-prod-azure.yml
name: Deploy to Azure Production

on:
  push:
    branches: [main]
  workflow_dispatch:  # Manual trigger

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [frontend, backend, csvtomdb]
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Build and push ${{ matrix.service }}
        run: |
          az acr login --name omispcacrprod
          docker build -t omispcacrprod.azurecr.io/omis-pc/${{ matrix.service }}:${{ github.sha }} .
          docker build -t omispcacrprod.azurecr.io/omis-pc/${{ matrix.service }}:latest .
          docker push omispcacrprod.azurecr.io/omis-pc/${{ matrix.service }}:${{ github.sha }}
          docker push omispcacrprod.azurecr.io/omis-pc/${{ matrix.service }}:latest
```

#### Phase 2: Add Watchtower for Automatic Updates (Optional Enhancement)

**What is Watchtower?**
Watchtower is a container that automatically pulls new images and restarts containers when updates are detected.

**How it works:**
1. Watchtower polls ACR every N minutes (configurable)
2. Compares running container image SHA with registry SHA
3. If new image found, pulls it and recreates container
4. Supports notifications (Slack, email, webhook)

**To add Watchtower to the VM:**

1. **Update `/opt/omis-pc/docker-compose.yml`** (via cloud-init or manual edit):
```yaml
services:
  # ... existing services ...

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /root/.docker/config.json:/config.json:ro  # ACR credentials
    environment:
      - WATCHTOWER_POLL_INTERVAL=300  # Check every 5 minutes
      - WATCHTOWER_CLEANUP=true       # Remove old images
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_NOTIFICATIONS=shoutrrr
      - WATCHTOWER_NOTIFICATION_URL=slack://webhook-url  # Optional
    command: --interval 300 --cleanup
```

2. **Create ACR service principal with pull access:**
```bash
# On your local machine
az ad sp create-for-rbac \
  --name omis-pc-watchtower \
  --role acrpull \
  --scope /subscriptions/<subscription-id>/resourceGroups/sazim-3dif-omis-pc-prod/providers/Microsoft.ContainerRegistry/registries/omispcacrprod

# Save output: appId, password, tenant
```

3. **Login to ACR on the VM** (creates `/root/.docker/config.json`):
```bash
ssh azureuser@20.245.121.120
sudo az login --service-principal \
  -u <appId> \
  -p <password> \
  --tenant <tenant>
sudo az acr login --name omispcacrprod
```

4. **Start Watchtower:**
```bash
cd /opt/omis-pc
docker compose up -d watchtower
docker compose logs -f watchtower  # Verify it's running
```

**Watchtower Security Considerations:**
- Service principal has ONLY `acrpull` role (cannot push/delete)
- Watchtower runs with access to Docker socket (required but privileged)
- Consider using Managed Identity instead of service principal (more secure)
- Limit update frequency to avoid rate limits
- Test in staging environment first

**Alternative to Watchtower:**
- **Manual deployments** via `./deploy.sh` script (current approach)
- **GitHub Actions SSH deployment** (workflow SSHs to VM and runs `docker compose pull && up -d`)
- **Azure Container Instances** with webhook triggers
- **Wait for AKS migration** (use GitOps with ArgoCD Image Updater)

#### Phase 3: Add Health Checks and Notifications

- [ ] Create GitHub Action that runs after deployment:
  - Wait 60 seconds for containers to start
  - Hit `https://omis-pc.example.com/api/health` (or IP if no domain)
  - Check frontend responds with 200
  - If health checks fail, send alert (GitHub issue, Slack, email)
- [ ] Optional: Configure Watchtower notifications:
```yaml
environment:
  - WATCHTOWER_NOTIFICATION_URL=slack://tokenA/tokenB/tokenC
  # Or email:
  - WATCHTOWER_NOTIFICATION_URL=smtp://username:password@host:port/?from=watchtower@example.com
```

#### Phase 4: TLS/HTTPS Setup (When Domain Available)

See [TLS_SETUP_GUIDE.md](./TLS_SETUP_GUIDE.md) for complete instructions.

**Quick summary:**
1. Point domain DNS to `20.245.121.120`
2. Set `DOMAIN=omis-pc.example.com` in `/opt/omis-pc/.env`
3. Update URLs in `.env`:
   ```bash
   WEB_CLIENT_BASE_URL=https://omis-pc.example.com
   NEXT_PUBLIC_API_BASE_URL=https://omis-pc.example.com/api/v1/
   NEXT_PUBLIC_WS_BASE_URL=wss://omis-pc.example.com
   ```
4. Restart: `docker compose up -d`
5. Caddy automatically provisions Let's Encrypt certificate
6. Update GitHub Actions workflows to use HTTPS URLs for health checks

**Caddy handles:**
- ✅ Automatic HTTPS certificate provisioning
- ✅ Certificate renewal (every 60 days)
- ✅ HTTP→HTTPS redirects
- ✅ Security headers (HSTS, X-Frame-Options, etc.)
- ✅ WebSocket upgrade to WSS

---

**Migration Path from Option D to Option A (Future AKS)**

When ready to migrate to AKS with GitOps:

1. **Keep existing workflows** - They already build and push to ACR
2. **Deploy AKS cluster** via Terraform (add module to `modules/azure/aks`)
3. **Install ArgoCD** on AKS cluster
4. **Configure ArgoCD Image Updater** to watch ACR
5. **Deploy Helm chart** from `deployToAzure/product-configurator-kubernetes`
6. **Switch DNS** from VM IP to AKS ingress IP
7. **Decommission VM** via `terraform destroy`

Option D provides a working production deployment while keeping the path to AKS/GitOps open.

### Option E – Azure Web App for Containers (multi-container) + GitHub Actions
A non-Kubernetes alternative that still removes VM management: run the existing docker-compose setup as an Azure Web App for Containers with a multi-container configuration file stored in Azure Storage.

**High-Level Architecture:**
```
┌───────────────────────────────────────────────────────────────┐
│                  GITHUB ACTIONS (CI)                           │
│  Build svc images → Push to ACR → Update compose file          │
└──────────────┬────────────────────────────────────────────────┘
               │  (release artifact)                              
┌──────────────▼──────────────────────────────┐                  
│   STORAGE (compose.yml + App Settings)      │                  
└──────────────┬──────────────────────────────┘                  
               │  (restart signal via API)                        
┌──────────────▼──────────────────────────────┐                  
│    AZURE WEB APP FOR CONTAINERS (Prod)      │                  
│  Pulls from ACR → spins FE/BE/csvtomdb      │                  
└─────────────────────────────────────────────┘                  
```

**Flow**
1. GitHub Actions builds/tests and pushes images to ACR (same as other options).
2. Workflow updates a `compose.webapp.yml` (multi-container definition) with new tags and uploads it to Azure Storage (or app settings) via `az webapp config container set`.
3. Azure Web App for Containers automatically pulls the referenced images from ACR and restarts containers. Staging slots can provide blue/green deploys without Kubernetes.
4. Auto image refresh can also be achieved by enabling continuous deployment on the Web App so that new tags trigger a restart.

**Detailed Multi-Container Web App Workflow:**
```
┌────────────────────────────────────────────────────────────────┐
│ STEP 1: DOCKER COMPOSE CONVERSION                              │
│ (Convert existing docker-compose.yml to Web App format)        │
│                                                                 │
│  Current: /opt/omis-pc/docker-compose.yml                      │
│  ┌──────────────────────────────────────────────────┐          │
│  │ services:                                         │          │
│  │   frontend:                                       │          │
│  │     image: omispcacrprod.../frontend:latest       │          │
│  │     ports: ["3000:3000"]                          │          │
│  │   backend:                                        │          │
│  │     image: omispcacrprod.../backend:latest        │          │
│  │     ports: ["5000:5000", "5001:5001"]             │          │
│  │   csvtomdb:                                       │          │
│  │     image: omispcacrprod.../csvtomdb:latest       │          │
│  │     ports: ["8080:8080"]                          │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                 │
│  Convert to: compose.webapp.yml (Web App schema)               │
│  ┌──────────────────────────────────────────────────┐          │
│  │ version: '3'                                      │          │
│  │ services:                                         │          │
│  │   frontend:                                       │          │
│  │     image: omispcacrprod.../frontend:${TAG}       │          │
│  │     environment:                                  │          │
│  │       - WEBSITES_PORT=3000  # Azure Web App var  │          │
│  │   backend:                                        │          │
│  │     image: omispcacrprod.../backend:${TAG}        │          │
│  │     environment:                                  │          │
│  │       - WEBSITES_PORT=5000                        │          │
│  │   csvtomdb:                                       │          │
│  │     image: omispcacrprod.../csvtomdb:${TAG}       │          │
│  │     environment:                                  │          │
│  │       - WEBSITES_PORT=8080                        │          │
│  └──────────────────────────────────────────────────┘          │
│                                                                 │
│  Limitations:                                                   │
│  ✗ No volume mounts (use Azure Files if needed)                │
│  ✗ No privileged containers                                    │
│  ✗ No custom networks (single flat network)                    │
│  ✓ Env vars via App Settings                                   │
│  ✓ Secrets via Key Vault references                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│ STEP 2: AZURE WEB APP PROVISIONING                             │
│                                                                  │
│  Terraform/Azure CLI:                                           │
│  ┌──────────────────────────────────────────────────┐           │
│  │ az appservice plan create \                      │           │
│  │   --name omis-pc-plan \                          │           │
│  │   --resource-group sazim-3dif-omis-pc-prod \     │           │
│  │   --is-linux \                                    │           │
│  │   --sku P1V3  # Premium (supports multi-contain) │           │
│  │                                                   │           │
│  │ az webapp create \                                │           │
│  │   --name omis-pc-webapp-prod \                   │           │
│  │   --resource-group sazim-3dif-omis-pc-prod \     │           │
│  │   --plan omis-pc-plan \                          │           │
│  │   --multicontainer-config-type compose \         │           │
│  │   --multicontainer-config-file compose.webapp.yml│           │
│  │                                                   │           │
│  │ # Enable ACR integration (Managed Identity)      │           │
│  │ az webapp config container set \                 │           │
│  │   --name omis-pc-webapp-prod \                   │           │
│  │   --resource-group sazim-3dif-omis-pc-prod \     │           │
│  │   --docker-registry-server-url omispcacrprod...  │           │
│  │   --enable-app-service-storage false             │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
│  Created Resources:                                             │
│  • App Service Plan: omis-pc-plan (P1V3: 1 core, 1.75GB)       │
│  • Web App: omis-pc-webapp-prod                                 │
│  • Deployment Slots: staging, production                        │
│  • Managed Identity: omis-pc-webapp-prod-identity               │
│  • Custom Domain: omis-pc.example.com (optional)                │
│  • SSL Certificate: Managed (Let's Encrypt) or custom          │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│ STEP 3: GITHUB ACTIONS DEPLOYMENT WORKFLOW                      │
│                                                                  │
│  .github/workflows/deploy-webapp.yml                            │
│  ┌──────────────────────────────────────────────────┐           │
│  │ name: Deploy to Azure Web App                    │           │
│  │                                                   │           │
│  │ on:                                               │           │
│  │   push:                                           │           │
│  │     branches: [main]                             │           │
│  │                                                   │           │
│  │ jobs:                                             │           │
│  │   build-and-deploy:                               │           │
│  │     runs-on: ubuntu-latest                        │           │
│  │     steps:                                        │           │
│  │       # BUILD PHASE (same as other options)       │           │
│  │       - checkout, build, test, push to ACR        │           │
│  │                                                   │           │
│  │       # DEPLOY PHASE (Web App specific)           │           │
│  │       - name: Update compose file                 │           │
│  │         run: |                                     │           │
│  │           export TAG=${{ github.sha }}            │           │
│  │           envsubst < compose.webapp.yml \         │           │
│  │             > compose.webapp.resolved.yml         │           │
│  │                                                   │           │
│  │       - name: Upload to Azure Storage             │           │
│  │         run: |                                     │           │
│  │           az storage blob upload \                │           │
│  │             --account-name omispcstorage \        │           │
│  │             --container-name configs \            │           │
│  │             --name compose-${{ github.sha }}.yml \│           │
│  │             --file compose.webapp.resolved.yml    │           │
│  │                                                   │           │
│  │       - name: Deploy to staging slot              │           │
│  │         run: |                                     │           │
│  │           az webapp config container set \        │           │
│  │             --name omis-pc-webapp-prod \          │           │
│  │             --resource-group ... \                │           │
│  │             --slot staging \                      │           │
│  │             --multicontainer-config-type compose \│           │
│  │             --multicontainer-config-file \        │           │
│  │               @compose.webapp.resolved.yml        │           │
│  │                                                   │           │
│  │           # Wait for deployment                   │           │
│  │           az webapp deployment slot poll \        │           │
│  │             --name omis-pc-webapp-prod \          │           │
│  │             --slot staging                        │           │
│  │                                                   │           │
│  │       - name: Health check staging                │           │
│  │         run: |                                     │           │
│  │           curl -f https://omis-pc-staging...      │           │
│  │                                                   │           │
│  │       - name: Swap slots (staging → production)   │           │
│  │         run: |                                     │           │
│  │           az webapp deployment slot swap \        │           │
│  │             --name omis-pc-webapp-prod \          │           │
│  │             --resource-group ... \                │           │
│  │             --slot staging \                      │           │
│  │             --target-slot production              │           │
│  └──────────────────────────────────────────────────┘           │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│ STEP 4: BLUE/GREEN DEPLOYMENT WITH SLOTS                        │
│                                                                  │
│  ┌───────────────────────────────────────────────────┐          │
│  │ BEFORE SWAP:                                      │          │
│  │                                                    │          │
│  │ Production Slot                  Staging Slot     │          │
│  │ ┌─────────────────────┐         ┌───────────────┐ │          │
│  │ │ frontend:xyz789abc  │         │ frontend:     │ │          │
│  │ │ backend:xyz789abc   │         │   abc123def ← │ │  NEW    │
│  │ │ csvtomdb:xyz789abc  │         │ backend:      │ │          │
│  │ │                     │         │   abc123def   │ │          │
│  │ │ Traffic: 100%       │         │ csvtomdb:     │ │          │
│  │ │ URL: omis-pc.com    │         │   abc123def   │ │          │
│  │ └─────────────────────┘         │               │ │          │
│  │                                  │ Traffic: 0%   │ │          │
│  │                                  │ URL: staging- │ │          │
│  │                                  │   omis-pc.com │ │          │
│  │                                  └───────────────┘ │          │
│  └───────────────────────────────────────────────────┘          │
│                                                                  │
│  Health checks on staging pass ✓                                │
│  Run: az webapp deployment slot swap ...                        │
│                                                                  │
│  ┌───────────────────────────────────────────────────┐          │
│  │ AFTER SWAP: (instant - no downtime)              │          │
│  │                                                    │          │
│  │ Production Slot                  Staging Slot     │          │
│  │ ┌─────────────────────┐         ┌───────────────┐ │          │
│  │ │ frontend:abc123def ←│  LIVE  │ frontend:     │ │          │
│  │ │ backend:abc123def   │         │   xyz789abc   │ │          │
│  │ │ csvtomdb:abc123def  │         │ backend:      │ │          │
│  │ │                     │         │   xyz789abc   │ │  BACKUP │
│  │ │ Traffic: 100%       │         │ csvtomdb:     │ │          │
│  │ │ URL: omis-pc.com    │         │   xyz789abc   │ │          │
│  │ └─────────────────────┘         │               │ │          │
│  │                                  │ Traffic: 0%   │ │          │
│  │                                  │ (instant      │ │          │
│  │                                  │  rollback)    │ │          │
│  │                                  └───────────────┘ │          │
│  └───────────────────────────────────────────────────┘          │
│                                                                  │
│  Swap time: ~5 seconds (network routing change only)            │
│  Rollback: az webapp deployment slot swap (reverse)             │
└──────────────────────────────────────────────────────────────────┘
```

**Container Networking & Routing:**
```
┌────────────────────────────────────────────────────────────────┐
│ AZURE WEB APP INTERNAL NETWORKING                              │
│                                                                 │
│  Internet (HTTPS requests)                                      │
│       │                                                         │
│       ▼                                                         │
│  ┌──────────────────────────────────────────┐                  │
│  │ Azure Front Door / App Gateway (optional)│                  │
│  │ • WAF rules                               │                  │
│  │ • SSL termination                         │                  │
│  │ • CDN for static assets                   │                  │
│  └────────────────┬─────────────────────────┘                  │
│                   │                                             │
│                   ▼                                             │
│  ┌────────────────────────────────────────────────────┐        │
│  │ App Service (omis-pc-webapp-prod)                  │        │
│  │                                                     │        │
│  │  Built-in Load Balancer                            │        │
│  │  ┌──────────────────────────────────────┐          │        │
│  │  │ Routing Rules (path-based):          │          │        │
│  │  │ • /          → frontend:3000         │          │        │
│  │  │ • /api/*     → backend:5000          │          │        │
│  │  │ • /ws        → backend:5001          │          │        │
│  │  │ • /csvtomdb  → csvtomdb:8080 (block) │          │        │
│  │  └──────────────────────────────────────┘          │        │
│  │                                                     │        │
│  │  Container Group (single VM host)                  │        │
│  │  ┌─────────────────────────────────────────────┐   │        │
│  │  │ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │        │
│  │  │ │frontend  │ │backend   │ │csvtomdb  │     │   │        │
│  │  │ │:3000     │ │:5000/5001│ │:8080     │     │   │        │
│  │  │ └──────────┘ └──────────┘ └──────────┘     │   │        │
│  │  │                                             │   │        │
│  │  │ Shared Network: 172.16.0.0/24 (internal)   │   │        │
│  │  │ DNS: Container names resolve via Docker    │   │        │
│  │  └─────────────────────────────────────────────┘   │        │
│  │                                                     │        │
│  │  ┌─────────────────────────────────────────────┐   │        │
│  │  │ App Settings (injected as env vars)         │   │        │
│  │  │ • DATABASE_URL → Azure PostgreSQL           │   │        │
│  │  │ • API_KEYS → Key Vault reference            │   │        │
│  │  │ • WEBSITES_ENABLE_APP_SERVICE_STORAGE=false │   │        │
│  │  └─────────────────────────────────────────────┘   │        │
│  └─────────────────────────────────────────────────────┘        │
│                   │                                             │
│                   ▼                                             │
│  ┌────────────────────────────────────────────────────┐        │
│  │ Azure Database for PostgreSQL                      │        │
│  │ (Private endpoint / VNet integration)              │        │
│  └────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

**Cost & Performance Comparison:**
```
┌──────────────────────────────────────────────────────────────────┐
│ PRICING COMPARISON (Monthly USD estimates)                       │
├───────────────────┬──────────────┬──────────────┬───────────────┤
│ Component         │ Current VM   │ Web App (E)  │ AKS (A/C)     │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Compute           │ D4ps_v5      │ P1V3         │ 3x D2s_v3     │
│                   │ $175/mo      │ $100/mo      │ $210/mo       │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Database          │ Included ↑   │ Included ↑   │ Included ↑    │
│ (B_Standard_B2ms) │              │              │               │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Load Balancer     │ None (Caddy) │ Built-in ✓   │ $20/mo        │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Storage (ACR)     │ $20/mo       │ $20/mo       │ $20/mo        │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Monitoring        │ Manual       │ Included ✓   │ $30/mo        │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ TOTAL             │ ~$195/mo     │ ~$120/mo     │ ~$260/mo      │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Management Time   │ 4 hrs/week   │ 1 hr/week    │ 2 hrs/week    │
│ (patching, etc.)  │              │              │               │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ Scaling           │ Manual       │ Auto (H/V)   │ Auto (H/V)    │
│                   │ (resize VM)  │ 0-30 inst.   │ 0-100 nodes   │
├───────────────────┼──────────────┼──────────────┼───────────────┤
│ SLA               │ 99.9%        │ 99.95%       │ 99.95%        │
│                   │ (single VM)  │ (multi-inst) │ (multi-zone)  │
└───────────────────┴──────────────┴──────────────┴───────────────┘

Recommendation: Option E for production if:
- ✓ No Kubernetes expertise in team
- ✓ Budget-conscious (~40% cheaper than AKS)
- ✓ Need deployment slots (blue/green)
- ✓ Azure-native monitoring acceptable
- ✗ Don't need multi-cluster orchestration
```

**Pros**
- Removes VM management while avoiding Kubernetes complexity.
- Built-in HTTPS, scaling, deployment slots, and diagnostics.
- Azure-native RBAC for ACR pulls; no SSH steps.

**Cons / Considerations**
- Limited container-to-container networking flexibility compared to full Kubernetes (e.g., no StatefulSets).
- Compose file must stay within Azure Web App schema (no privileged containers, limited volume mounts).
- csvtomdb service startup resources must fit within Web App SKU.

**Implementation Tasks**
- [ ] Export current `docker-compose` definition to Azure Web App multi-container format.
- [ ] Create Web App for Containers (prod + staging) with Managed Identity granted ACR pull.
- [ ] Extend GitHub Actions workflow to run `az webapp config container set --slot ...` after pushing images.
- [ ] Configure deployment slot swap approvals for prod, ensuring health checks before swap.

## 6. Visual Comparison of All Options

### Quick Decision Matrix
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                      CI/CD OPTIONS COMPARISON MATRIX                                             │
├─────────────┬───────────┬───────────┬───────────┬──────────────┬─────────────────────────────────┤
│ CRITERIA    │ OPTION A  │ OPTION B  │ OPTION C  │ OPTION D     │ OPTION E                        │
│             │ GitOps    │ Azure     │ Direct    │ VM Auto      │ Web App                         │
│             │ (ArgoCD)  │ DevOps    │ to AKS    │ (Current)    │ Containers                      │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Setup Time  │ 2-3 weeks │ 2 weeks   │ 1 week    │ 3-5 days     │ 1 week                          │
│             │ ████████  │ ███████   │ ████      │ ██           │ ████                            │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Complexity  │ High      │ Medium    │ Low       │ Very Low     │ Low                             │
│             │ ████████  │ █████     │ ███       │ █            │ ███                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Cost/Month  │ ~$260     │ ~$280     │ ~$260     │ ~$195        │ ~$120                           │
│             │ ███████   │ ████████  │ ███████   │ █████        │ ███                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Auto Deploy │ Yes       │ Yes       │ Yes       │ Optional     │ Yes                             │
│             │ ✓✓✓       │ ✓✓✓       │ ✓✓✓       │ ✓✓ (Watch)   │ ✓✓✓                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Rollback    │ Git       │ Git/      │ Helm      │ Docker       │ Slot Swap                       │
│             │ Revert    │ Pipeline  │ Rollback  │ Compose      │ (Instant)                       │
│             │ ✓✓✓       │ ✓✓        │ ✓✓        │ ✓            │ ✓✓✓                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Audit Trail │ Git       │ Azure     │ GitHub    │ Docker       │ Azure Portal                    │
│             │ History   │ DevOps    │ Actions   │ Logs         │ + GH Actions                    │
│             │ ✓✓✓       │ ✓✓✓       │ ✓✓        │ ✓            │ ✓✓                              │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Drift       │ Auto      │ Manual    │ Manual    │ None         │ None                            │
│ Detection   │ Detect    │ (Config)  │           │              │                                 │
│             │ ✓✓✓       │ ✓         │ ✗         │ ✗            │ ✗                               │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Multi-Env   │ Excellent │ Good      │ Medium    │ Poor         │ Good                            │
│ Support     │ (GitOps)  │ (Stages)  │ (Scripts) │ (Manual)     │ (Slots)                         │
│             │ ✓✓✓       │ ✓✓        │ ✓         │ ✗            │ ✓✓                              │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Blue/Green  │ ArgoCD    │ Manual    │ Manual    │ No           │ Built-in                        │
│ Deploy      │ Rollouts  │ Script    │ Script    │              │ Slot Swap                       │
│             │ ✓✓        │ ✓         │ ✓         │ ✗            │ ✓✓✓                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Learning    │ Steep     │ Medium    │ Low       │ Minimal      │ Low                             │
│ Curve       │ (K8s+Git) │ (ADO)     │ (K8s)     │ (Docker)     │ (Azure)                         │
│             │ ████████  │ █████     │ ███       │ █            │ ███                             │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Scalability │ Excellent │ Excellent │ Excellent │ Poor         │ Good                            │
│             │ (AKS)     │ (AKS)     │ (AKS)     │ (1 VM)       │ (30 inst)                       │
│             │ ✓✓✓       │ ✓✓✓       │ ✓✓✓       │ ✗            │ ✓✓                              │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Requires    │ Yes       │ Yes       │ Yes       │ No           │ No                              │
│ AKS         │ (Future)  │ (Future)  │ (Future)  │              │                                 │
│             │ ⏳        │ ⏳        │ ⏳        │ ✓            │ ✓                               │
├─────────────┼───────────┼───────────┼───────────┼──────────────┼─────────────────────────────────┤
│ Best For    │ Multi-    │ Enterprise│ Simple    │ Quick        │ Cost-effective                  │
│             │ cluster   │ with      │ K8s       │ automation   │ PaaS, no K8s                    │
│             │ future    │ Azure     │ today     │ on existing  │ expertise                       │
│             │           │ ecosystem │           │ VM           │                                 │
└─────────────┴───────────┴───────────┴───────────┴──────────────┴─────────────────────────────────┘
```

### Deployment Flow Visualization (Side-by-Side)
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                 DEPLOYMENT FLOWS                                                 │
│                                                                                                  │
│  OPTION A (GitOps)     OPTION B (ADO)       OPTION C (Direct)   OPTION D (VM)    OPTION E (Web) │
│  ┌───────────┐         ┌───────────┐        ┌───────────┐       ┌───────────┐   ┌───────────┐ │
│  │ GitHub    │         │ Azure     │        │ GitHub    │       │ GitHub    │   │ GitHub    │ │
│  │ Actions   │         │ Pipelines │        │ Actions   │       │ Actions   │   │ Actions   │ │
│  └─────┬─────┘         └─────┬─────┘        └─────┬─────┘       └─────┬─────┘   └─────┬─────┘ │
│        │ build               │ build              │ build             │ build         │ build │
│        ▼                     ▼                    ▼                   ▼               ▼       │
│  ┌───────────┐         ┌───────────┐        ┌───────────┐       ┌───────────┐   ┌───────────┐ │
│  │    ACR    │         │    ACR    │        │    ACR    │       │    ACR    │   │    ACR    │ │
│  └─────┬─────┘         └─────┬─────┘        └─────┬─────┘       └─────┬─────┘   └─────┬─────┘ │
│        │ webhook             │ PR create          │ helm cmd          │ watch         │ config│
│        ▼                     ▼                    ▼                   ▼               ▼       │
│  ┌───────────┐         ┌───────────┐        ┌───────────┐       ┌───────────┐   ┌───────────┐ │
│  │ GitOps    │         │ GitOps    │        │  kubectl  │       │Watchtower │   │ Storage + │ │
│  │   Repo    │         │   Repo    │        │  (direct) │       │(optional) │   │ az webapp │ │
│  └─────┬─────┘         └─────┬─────┘        └─────┬─────┘       └─────┬─────┘   └─────┬─────┘ │
│        │ sync                │ sync/apply         │ apply             │ pull          │ restart│
│        ▼                     ▼                    ▼                   ▼               ▼       │
│  ┌───────────┐         ┌───────────┐        ┌───────────┐       ┌───────────┐   ┌───────────┐ │
│  │  ArgoCD   │         │ArgoCD/Flux│        │    AKS    │       │Docker     │   │  App Svc  │ │
│  │  on AKS   │         │  on AKS   │        │  Cluster  │       │ Compose   │   │Multi-Cont │ │
│  └─────┬─────┘         └─────┬─────┘        └─────┬─────┘       └─────┬─────┘   └─────┬─────┘ │
│        │ deploy              │ deploy             │ running           │ running       │ slots │
│        ▼                     ▼                    ▼                   ▼               ▼       │
│  ┌───────────┐         ┌───────────┐        ┌───────────┐       ┌───────────┐   ┌───────────┐ │
│  │    AKS    │         │    AKS    │        │    AKS    │       │    VM     │   │  Staging  │ │
│  │  Cluster  │         │  Cluster  │        │  Cluster  │       │ (Single)  │   │   Prod    │ │
│  │ (running) │         │ (running) │        │ (running) │       │           │   │ (Swap)    │ │
│  └───────────┘         └───────────┘        └───────────┘       └───────────┘   └───────────┘ │
│                                                                                                  │
│  Time: ~5min           Time: ~8min          Time: ~4min        Time: ~3min    Time: ~5min      │
│  Manual: None          Manual: Approve      Manual: None       Manual: SSH    Manual: Approve  │
│  Rollback: Git         Rollback: Git/Re-run Rollback: Helm     Rollback: Tag  Rollback: Swap   │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Decision Tree
```
START: Need CI/CD for OMIS Product Configurator
  │
  ├─ Do you have AKS provisioned today?
  │  │
  │  ├─ NO → Is budget a primary concern?
  │  │  │
  │  │  ├─ YES → OPTION E (Web App) ← Cheapest PaaS, built-in slots
  │  │  │
  │  │  └─ NO → Do you need immediate automation?
  │  │     │
  │  │     ├─ YES → OPTION D (VM Auto) ← Quick win, existing infra
  │  │     │
  │  │     └─ NO → Wait for AKS, then choose A/B/C
  │  │
  │  └─ YES (AKS exists) → Do you need multi-cluster/multi-env GitOps?
  │     │
  │     ├─ YES → Do you want Azure-native tooling?
  │     │  │
  │     │  ├─ YES → OPTION B (Azure DevOps + Flux)
  │     │  │         ↑ Enterprise, compliance, Key Vault, approvals
  │     │  │
  │     │  └─ NO → OPTION A (GitHub Actions + ArgoCD)
  │     │            ↑ Open source, proven GitOps pattern from k8s-dev
  │     │
  │     └─ NO (simple, single cluster) → OPTION C (Direct Deploy)
  │                  ↑ Low complexity, good for small teams
  │
RECOMMENDATION:
  - Immediate (this week): OPTION D (add Watchtower to VM)
  - Short-term (1-2 months): OPTION E (migrate to Web App for Containers)
  - Long-term (3-6 months): OPTION A (AKS + GitOps when K8s skills mature)
```

## 7. Recommendation & Rollout Strategy
1. **Phase 0 (1 week)** – Implement Option D to close automation gap immediately on the existing VM.
   - Action items: clone the current staging GitHub Actions workflow from `omis/product-configurator`, add prod jobs/tags, and wire Watchtower onto the VM.
2. **Phase 1 (2-3 weeks)** – Decide between Option E (Web App) and future AKS path based on infra readiness; pilot Option E for staging if AKS timeline slips.
3. **Phase 2 (3-4 weeks)** – If AKS is prioritized, stand up GitOps stack mirroring `infra/k8s-dev` (Option A). Otherwise, harden Web App deployment with slots/monitoring.
4. **Phase 3 (Ongoing)** – Pick long-term pipeline host (GitHub Actions vs. Azure DevOps) and extend observability/alerting.

## 7. Key Workstreams & Owners
| Workstream | Deliverables | Owner |
| --- | --- | --- |
| CI Pipeline Authoring | GitHub Actions YAML, caching, test matrices | App Eng Team |
| Container Registry & Secrets | ACR RBAC, Managed Identity for ArgoCD Image Updater or Web App | Infra |
| Runtime Platform | Watchtower on VM, Web App config, or AKS GitOps stack | Infra |
| Application Config | Ensure `.env`/App Settings/Helm values match target platform | App Eng + Infra |
| Observability | Pipeline notifications, uptime checks, slot health probes | DevEx |

## 8. Open Questions
1. Which runtime are we targeting once VM automation is in place—Web App (Option E) or AKS (Option A/C)?
2. Target go-live date for AKS/Web App? Helps pick Option A vs. Option E sequencing.
3. Required compliance/audit tooling? (Drives GitHub vs. Azure DevOps decision.)
4. Need for blue/green or canary rollouts? (Would introduce slots in Option E or Argo Rollouts in Option A.)
5. Should dev environment remain on DigitalOcean (current `k8s-dev`) or consolidate into Azure once GitOps is available?

Answering these questions will lock in exact tooling, secrets strategy, and sprint plan.
