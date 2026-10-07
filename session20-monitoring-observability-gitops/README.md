# Session 20 — Monitoring, Observability & GitOps

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** minikube 2-node · Kubernetes v1.37.0 · Prometheus v3.15.0 · Grafana 12.3.1 · Argo CD

Everything below ran on the live cluster. Transcripts in [`logs/`](./logs),
screenshots in [`screenshots/`](./screenshots).

---

## Task 1 — Monitoring

Prometheus and Grafana installed with **Helm** (Session 15's tooling):

```
$ helm list -n monitoring
NAME         REVISION  STATUS    CHART                APP VERSION
grafana      1         deployed  grafana-10.5.15      12.3.1
prometheus   2         deployed  prometheus-29.36.0   v3.15.0
```

### What it scrapes — 11 targets across 5 jobs

```
kubernetes-api-servers        1 target
kubernetes-nodes              2 targets   (kubelet)
kubernetes-nodes-cadvisor     2 targets   (per-container metrics)
kubernetes-service-endpoints  5 targets   (kube-state-metrics, node-exporter)
prometheus                    1 target    (itself)
```

Note `node-exporter` runs as a **DaemonSet** — one pod per node, exactly the
pattern from Session 10, and the reason there are 2 of each node-level target.

### Metrics — CPU, memory and application health

Real PromQL against the live server:

```
$ 100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
  192.168.49.2:9100   CPU busy:  2.86%
  192.168.49.3:9100   CPU busy:  2.46%

$ 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
  192.168.49.2:9100   memory used: 39.27%
  192.168.49.3:9100   memory used: 38.45%

$ sum by (namespace) (kube_pod_status_ready{condition="true"})
  argocd        6 ready pods      monitoring   4 ready pods
  kube-system  11 ready pods      session20    2 ready pods
```

### Alerts — defined, loaded, and actually firing

[`monitoring/alert-rules.yaml`](./monitoring/alert-rules.yaml), applied with
`helm upgrade` (revision 1 → 2):

```
NodeMemoryHigh           for=30s    warning
PodNotReady              for=300s   critical
PodRestartingTooOften    for=300s   warning
```

The full lifecycle, observed:

```
# after ~30s
NodeMemoryHigh   PENDING   192.168.49.2:9100 memory is 40.5%.
# after the 'for' duration elapsed
NodeMemoryHigh   FIRING    192.168.49.2:9100 memory is 40.6%.
PodNotReady      PENDING   Pod argocd/argocd-applicationset-controller-... not ready
```

An alert is **pending** while its condition holds but the `for:` duration has not
elapsed, and only then becomes **firing**. That delay is what stops a 5-second
CPU spike paging someone.

> The 20% memory threshold is deliberately low so the rule fires on an idle lab
> cluster — production would use `>85% for 10m`. `PodRestartingTooOften` is the
> genuinely useful one: it catches the CrashLoopBackOff from Session 14
> automatically, before a human notices.

### Grafana, wired to Prometheus

```
$ curl -u "admin:$GRAFANA_PW" .../api/health
{ "database": "ok", "version": "12.3.1" }

$ curl -u "admin:$GRAFANA_PW" .../api/datasources
datasource: Prometheus (prometheus) -> http://prometheus-server.monitoring.svc.cluster.local  default=True

# query Prometheus THROUGH Grafana's proxy, proving the wiring end to end
$ .../api/datasources/proxy/1/api/v1/query?query=up
scrape targets up: 11 of 11
```

Querying *through* Grafana's datasource proxy is the check worth doing — a
datasource can exist in config and still be unreachable from the Grafana pod.

> **The Session 17 gate caught my own Session 20 code.** My first version of these
> commands used a literal `-u admin:admin`, and `gitleaks` — running with the
> config written in Session 17 — flagged 5 new `curl-auth-user` findings across
> this README and its log. The fix was to read the password from the cluster
> Secret into `$GRAFANA_PW` so the credential never reaches a committed file.
> That is the whole argument for a secret scanner: it caught a careless habit in
> fresh work, not a historical mistake.

📄 [`logs/01-monitoring.txt`](./logs/01-monitoring.txt) · 📸 [`01-monitoring.png`](./screenshots/01-monitoring.png)

---

## Task 2 — Observability

Full write-up: **[`observability/README.md`](./observability/README.md)**

It covers monitoring vs observability, the three pillars with their individual
limits, how they compose during an incident, the common tooling, and the
Kubernetes-specific sources (node-exporter, cAdvisor, kube-state-metrics, and why
metrics-server is *not* a monitoring system).

The short version:

```
METRIC   tells you THAT something is wrong    ->  wakes you up
TRACE    tells you WHERE the time goes        ->  narrows it to a service
LOG      tells you WHY                        ->  the actual error
```

A `trace_id` propagated into log lines is what joins them. Without it you are
correlating by timestamp and guessing.

Each pillar's limit matters as much as its strength: metrics cannot carry high
cardinality (a `user_id` label creates one time series per user), logs are
expensive to aggregate, and traces require instrumentation and sampling.

---

## Task 3 — GitOps

### What it is

Git is the **source of truth**. The desired state lives in a repository; an
in-cluster agent continuously reconciles the cluster toward it. Nobody runs
`kubectl apply` against the app.

| | Push (traditional CI/CD) | **Pull (GitOps)** |
|---|---|---|
| Who deploys | CI runner reaches into the cluster | an **agent inside** the cluster pulls |
| Credentials | cluster admin creds live in CI | **none leave the cluster** |
| Drift | undetected | detected and reverted |
| Rollback | re-run a pipeline | `git revert` |
| Audit trail | pipeline logs | **the git history** |

The credential point is the big one. Session 16's CD pipeline needed a path into
the cluster; a GitOps agent needs only *read* access to a repo.

### The live demo — syncing from this very repository

[`gitops/argocd-application.yaml`](./gitops/argocd-application.yaml) points Argo CD
at the real public repo:

```yaml
source:
  repoURL: https://github.com/thrishaldoma/devops-homework.git
  targetRevision: main
  path: session20-monitoring-observability-gitops/gitops-app
syncPolicy:
  automated:
    prune: true      # delete cluster resources removed from Git
    selfHeal: true   # revert manual changes made against the cluster
```

Applying that Application object is the **only** imperative step. After it:

```
$ kubectl get application -n argocd session20-mini
SYNC     HEALTH    REVISION
Synced   Healthy   b40ff23d6bcaf13354229d0b025249c45c2245a6

Namespace/session20        Synced
Service/session20-mini     Synced
Deployment/session20-mini  Synced
```

The deployment, service and namespace in [`gitops-app/`](./gitops-app) were
created by Argo CD reading Git — not by me running `kubectl`.

### Continuous reconciliation — the property that matters

Scaling the deployment by hand, the way an engineer would mid-incident:

```
$ kubectl scale deployment session20-mini -n session20 --replicas=5
immediately after: 5

10s  replicas=5  sync=Synced
20s  replicas=2  sync=Synced     <- reverted to the value in Git
30s  replicas=2  sync=Synced
```

Nobody reverted that. `selfHeal: true` did, because Git says `replicas: 2`.
**The cluster is not the source of truth.** A manual change is drift, and drift
gets undone — which is also why a "quick fix" in production must go through a
commit, or it will silently disappear.

📄 [`logs/02-gitops-argocd.txt`](./logs/02-gitops-argocd.txt) · 📸 [`02-gitops-argocd.png`](./screenshots/02-gitops-argocd.png)

### Argo CD refused the repo first — and was right to

```
Failed to load target state: ... repository contains out-of-bounds symlinks.
file: 01-linux/links-lab/broken
```

A supply-chain control, not a bug. An out-of-bounds symlink can point at anything
on the repo-server's filesystem — `/etc/passwd`, a mounted token — and Argo CD
would render it into a manifest. So it refuses the whole repository.

The offending file is `broken -> /nonexistent` from **Session 1's links lab**, a
deliberately broken symlink whose creation is documented with captured output in
that session's README. Rewriting it would make that evidence inconsistent with
its own artifact, so it stays.

Resolution: `ARGOCD_REPO_SERVER_ALLOW_OUT_OF_BOUNDS_SYMLINKS=true`, a flag Argo CD
marks *"(not recommended)"*. That is defensible **here and nowhere else** — a
single-author homework monorepo, a known benign symlink, a public repo with
nothing on the repo-server worth exfiltrating.

**The production answer is different: use a separate config repository** holding
only manifests. That is standard GitOps practice for reasons beyond this symlink
— a tighter RBAC surface, a clean audit trail of deploys, and application commits
that do not trigger reconciliation. The monorepo here is a homework constraint,
not a model to copy.

---

## Index

| Path | Contents |
|---|---|
| [`monitoring/alert-rules.yaml`](./monitoring/alert-rules.yaml) | Prometheus alerting rules |
| [`observability/README.md`](./observability/README.md) | the three pillars (Task 2) |
| [`gitops-app/`](./gitops-app) | **the manifests Argo CD watches** — the source of truth |
| [`gitops/argocd-application.yaml`](./gitops/argocd-application.yaml) | the Application object, deliberately outside the watched path |

## Reproducing

```bash
# monitoring
helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace \
  --set alertmanager.enabled=false --set server.persistentVolume.enabled=false
helm install grafana grafana/grafana -n monitoring --set persistence.enabled=false
helm upgrade prometheus prometheus-community/prometheus -n monitoring \
  --reuse-values -f monitoring/alert-rules.yaml
kubectl port-forward -n monitoring svc/prometheus-server 19090:80

# gitops
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f gitops/argocd-application.yaml
kubectl scale deployment session20-mini -n session20 --replicas=5   # watch it revert
```
