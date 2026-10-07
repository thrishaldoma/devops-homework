# Session 21 — DevOps Final Capstone: TaskBoard

This folder holds the Session 21 reference project, **TaskBoard**, exactly as it
was supplied with the course, plus the evidence from running and reviewing it.

The course's own write-up is preserved unchanged as
[TASKBOARD-REFERENCE.md](TASKBOARD-REFERENCE.md) — it is the teaching material
and explains what each tool is for. This file is the engineering record: what
the project is, what happened when it was actually run, and what was found.

> **Before submitting this as a capstone, read [GRADING.md](GRADING.md) §Grading
> Policy.** It states that *"a direct clone of the TaskBoard reference project
> without meaningful changes receives a zero for all modules"* and that *"the
> application domain must be your own"*. TaskBoard is the worked example to
> imitate structurally, not the thing to hand in. The DevOps layer may follow
> the same architecture.

---

## 1. What TaskBoard is

A small project-management application, used as a vehicle for taking a real
service from a laptop to a monitored Kubernetes cluster.

```
Browser  ──►  Nginx (frontend container)
                 │  serves the React bundle
                 └─ proxies /api ──►  FastAPI (backend container)
                                          │
                                          └──►  PostgreSQL
                                                   ▲
                                          Alembic migrations
```

| Layer | Technology |
|---|---|
| Frontend | React 18 + Vite, built to static files, served by Nginx |
| Backend | FastAPI (Python 3.12), SQLAlchemy 2.0 ORM, Alembic migrations |
| Database | PostgreSQL 16 |
| Metrics | `prometheus-fastapi-instrumentator`, exposed at `/metrics` |
| Packaging | Two Docker images; Docker Compose for local use |
| Kubernetes | Helm chart with Deployments, Services, Ingress, HPA, ServiceMonitor |
| Infrastructure | Terraform targeting AWS VPC + EKS |
| Pipeline | GitHub Actions: test → build/scan/push → deploy |

### Folder map

| Path | Contents |
|---|---|
| `backend/app/` | `main.py` (routes), `models.py`, `schemas.py`, `db.py`, `config.py` |
| `backend/alembic/` | Migration environment and `versions/0001_create_tasks.py` |
| `backend/tests/` | `test_api.py` — three tests |
| `frontend/` | React source, `nginx.conf`, multi-stage `Dockerfile` |
| `helm/taskboard/` | Chart, values for dev/prod, templates |
| `k8s/` | `namespace.yaml` |
| `terraform/` | VPC + EKS via the community registry modules |
| `monitoring/` | Prometheus/Grafana Helm values |
| `troubleshooting/` | Deliberately broken manifests for the lab |
| `scripts/` | `load-test.sh` |
| `.github/workflows/` | `ci-cd.yml` (see Finding 7 — it does not run from here) |

### HTTP API

```
GET    /                     service metadata
GET    /health               liveness   — does not touch the database
GET    /ready                readiness  — verifies database access
GET    /metrics              Prometheus exposition
GET    /docs                 Swagger UI

GET    /api/tasks            list
POST   /api/tasks            create                → 201
GET    /api/tasks/stats      counts by status
GET    /api/tasks/{id}       fetch                 → 404 when absent
PUT    /api/tasks/{id}       update
DELETE /api/tasks/{id}       delete                → 204
```

### Running it

```bash
docker compose up --build        # frontend, backend and postgres
# UI       http://localhost:3000
# API docs http://localhost:8000/docs
docker compose down -v           # stop and drop the database volume
```

---

## 2. What was actually run, and what was only read

Being explicit about this, because the two are not the same kind of evidence.

| Area | Status |
|---|---|
| Docker Compose stack (3 services) | **Run** — built and started, all services healthy |
| Full CRUD against the REST API | **Run** — POST/GET/PUT/DELETE, including 204 and 404 |
| Browser UI | **Run** — real screenshots, desktop and mobile widths |
| Swagger UI | **Run** — real screenshot |
| `pytest` | **Run** — on Python 3.12 with the project's pinned requirements |
| Trivy image scans | **Run** — both images, with the pipeline's own flags |
| Container user / hardening | **Run** — checked in the image config and in the live container |
| Helm chart | **Reviewed statically** — `helm lint` and `helm template`; nothing deployed |
| Terraform | **Reviewed statically** — `terraform init` attempted and failed |
| GitHub Actions pipeline | **Reviewed statically** — never executed (Finding 7) |
| Kubernetes cluster, AWS | **Not used** — nothing was deployed to either |

### Environment deviations

Stated rather than hidden, as in the other sessions in this repository.

1. **The UI was published on `http://localhost:3080`, not `:3000`.** Host ports
   3000 and 3001 were both already bound by unrelated `node` processes on this
   machine. Nothing inside the stack changed — only the host-side mapping, via
   an override file kept outside the repository:

   ```yaml
   # port-override.yml
   services:
     frontend:
       ports: !override          # replaces the list; Compose MERGES sequences
         - "3080:80"             # by default, which would keep the 3000 clash
   ```
   ```bash
   docker compose -f docker-compose.yml -f port-override.yml up -d
   ```

2. **Tests ran in a scratch copy of `backend/`.** The suite writes a `test.db`
   into its working directory and nothing in the repository ignores that file,
   so running in place would have left an artefact behind. A throwaway
   virtualenv on Python 3.12 was used because this machine's default `python3`
   is 3.9, which the project does not support.

3. **No AWS account and no Kubernetes deployment.** See Findings 5 and 6.

---

## 3. Findings

Running the project surfaced defects that stop several of the graded modules
from working as shipped. Each row links to the log holding its evidence.

| # | Module | Finding | Evidence |
|---|---|---|---|
| 1 | M2 | **The test suite fails from a clean checkout** — 1 of 3 tests errors with `no such table: tasks` | [02-pytest](logs/02-pytest.txt) |
| 2 | M2 | Only **3 tests** exist; the rubric requires **≥5 across ≥3 endpoints** | [GRADING.md](GRADING.md) |
| 3 | M4 | **The frontend image runs as root**; the rubric awards points for non-root | [03](logs/03-image-hardening-and-trivy.txt) |
| 4 | M6 | **Both images fail the Trivy gate** under the pipeline's own settings | [03](logs/03-image-hardening-and-trivy.txt) |
| 5 | M7 | **`terraform init` exits 1** — `main.tf` and `versions.tf` are not valid HCL | [05](logs/05-terraform-review.txt) |
| 6 | M7 | `terraform.tfvars.example` is **absent** | [05](logs/05-terraform-review.txt) |
| 7 | M5 | The workflow is **nested**, so GitHub never runs it | [06](logs/06-cicd-workflow-review.txt) |
| 8 | M5 | `trivy-action@0.30.0` — **that tag does not exist** (all tags are `v`-prefixed) | [06](logs/06-cicd-workflow-review.txt) |
| 9 | M8 | The **Ingress points at a Service that is not created**, and at the wrong port | [04](logs/04-kubernetes-helm-review.txt) |
| 10 | M8 | The **frontend cannot start in Kubernetes** — Nginx cannot resolve `backend` | [04](logs/04-kubernetes-helm-review.txt) |
| 11 | M8 | Default images are `ghcr.io/YOUR_ORG/...:latest` placeholders | [04](logs/04-kubernetes-helm-review.txt) |
| 12 | — | The **database password is committed** in `values.yaml` | [04](logs/04-kubernetes-helm-review.txt) |
| 13 | — | The UI hardcodes another person's name, **"Nensi Ravaliya"** | [browser-01](screenshots/browser-01-application-dashboard.png) |

### The three worth understanding

**Finding 1 — why the tests fail.** `tests/test_api.py` builds its client at
module scope:

```python
client = TestClient(app)
```

Starlette only runs an application's startup/lifespan events when `TestClient`
is used as a **context manager**. `app/main.py` creates the schema inside an
`@app.on_event("startup")` handler, so with a bare client that handler never
fires and the table is never created. Demonstrated directly — same app, same
engine, two ways of constructing the client:

```
bare  TestClient(app)        -> tables: []
with  TestClient(app) as ctx -> tables: ['tasks']
```

The two tests that pass (`/health`, `/`) never touch the database. Since the
pipeline's `test` job runs `pytest -q`, this alone would stop every later job.

**Finding 4 — what Trivy found.** All three HIGH findings in the backend are the
same package: `starlette 0.41.3`, pulled in transitively by the pinned
`fastapi==0.115.6`. They are a denial of service via Range-header merging
(CVE-2025-62727), SSRF and NTLM credential theft via UNC paths in `StaticFiles`
(CVE-2026-48818), and silently ignored form-size limits (CVE-2026-54283). All
three are marked **fixed** upstream, which is precisely why `--ignore-unfixed`
does not suppress them — that flag only hides vulnerabilities with no available
fix. A current `fastapi` resolves `starlette 1.7.0`, above all three fixed
versions, clearing the set. The frontend's 44 findings are OS packages from its
`nginx:1.27-alpine` base, so the fix there is a newer base image, not a source
change.

**Finding 10 — why the frontend cannot run in Kubernetes.** `nginx.conf` proxies
`/api` to the literal host `backend`. Nginx resolves a static `proxy_pass`
hostname once, at startup, and refuses to start if it cannot. Under Compose the
service genuinely is named `backend`, so it works. The Helm chart names it
`taskboard-taskboard-backend`, so the pod would CrashLoopBackOff:

```
nginx: [emerg] host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:13
container exit code: 1
```

### What the project gets right

Worth saying plainly: the architecture is sound. Job ordering in the pipeline is
correct (test → build/scan/push → deploy), images are tagged with the commit SHA
as M5 requires, `GITHUB_TOKEN` is used instead of a user-managed registry
secret, permissions are declared per job, the backend image is multi-stage and
non-root, `/health` and `/ready` are properly distinguished, the chart meets the
two-replica requirement with ClusterIP Services, and an HPA and ServiceMonitor
are both present. The defects above are fixable in an afternoon; the shape of
the thing is right.

---

## 4. Evidence

### Logs — real captured output, the primary evidence

| Log | Covers |
|---|---|
| [01-local-stack.txt](logs/01-local-stack.txt) | Compose services, images, health/ready, full CRUD, Nginx proxy, metrics |
| [02-pytest.txt](logs/02-pytest.txt) | The suite, the failure, and a direct demonstration of its root cause |
| [03-image-hardening-and-trivy.txt](logs/03-image-hardening-and-trivy.txt) | Container users, image sizes, both Trivy scans, gate exit codes |
| [04-kubernetes-helm-review.txt](logs/04-kubernetes-helm-review.txt) | `helm lint`, rendered manifests, Ingress/Service mismatch, Nginx startup failure |
| [05-terraform-review.txt](logs/05-terraform-review.txt) | Per-file HCL validity, `init` failure and exit code, LocalStack EKS availability |
| [06-cicd-workflow-review.txt](logs/06-cicd-workflow-review.txt) | Workflow location, action tag resolution, pinning, owner case, missing secret |

### Screenshots

Two kinds, labelled so there is no ambiguity:

**Real browser captures** (Playwright against the running stack):

| File | Shows |
|---|---|
| [browser-01-application-dashboard.png](screenshots/browser-01-application-dashboard.png) | The app with six seeded tasks; KPI cards match the API exactly |
| [browser-02-swagger-api-docs.png](screenshots/browser-02-swagger-api-docs.png) | Swagger UI listing all ten endpoints |
| [browser-03-create-task-modal.png](screenshots/browser-03-create-task-modal.png) | The create-task dialog |
| [browser-04-responsive-mobile.png](screenshots/browser-04-responsive-mobile.png) | 390 px width — sidebar collapses, cards reflow |

**Rendered from the logs** — `log-*.png` are terminal-styled renderings of the
`.txt` files above, produced by `_tools/render-terminal.py`. Nothing in them is
re-typed; the `.txt` files remain the primary evidence.

### Screenshots the rubric asks for that are not here

| Asked for | Why not |
|---|---|
| `kubectl get pods/svc`, `helm list`, app via Ingress | Nothing was deployed; Findings 9–11 would have to be fixed first |
| Prometheus Targets `UP`, Grafana panel | Follows from the above — there is no running workload to scrape |
| GHCR package page with SHA tags | The pipeline never ran (Finding 7), so no image was published |
| AWS Console showing VPC + EKS | No AWS account. `terraform init` also fails (Finding 5), and the LocalStack container used in Sessions 18–19 is the **community** edition, which does not offer EKS at all |

---

## 5. Reproducing this

```bash
cd session21-python

# 1. the stack  (use the override from §2 if port 3000 is taken)
docker compose up --build -d
curl -s localhost:8000/health && curl -s localhost:8000/api/tasks/stats

# 2. the tests  (Python 3.12; copy elsewhere first to avoid a stray test.db)
cd backend && python3.12 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
./.venv/bin/python -m pytest -v

# 3. the scans
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  session21-python-backend:latest

# 4. the chart
helm lint ./helm/taskboard
helm template taskboard ./helm/taskboard --set ingress.enabled=true

# 5. the infrastructure
cd terraform && terraform init
```

### Tearing down

The stack was torn down once this evidence was captured, so nothing is left
running: containers, the Postgres volume, the network and both built images
were all removed. See [`logs/99-session21-teardown.log`](../logs/99-session21-teardown.log)
in the repository root.

```bash
cd session21-python
docker compose down -v           # removes containers and the database volume
docker rmi session21-python-backend:latest session21-python-frontend:latest
```
