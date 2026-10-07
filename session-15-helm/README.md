# Session 15 — Helm

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · **Helm v4.3.0** · Kubernetes v1.37.0 · 2-node minikube

Charts come from the course repository (`devops-heros/session-15-helm`). All output
is real; transcripts in [`logs/`](./logs), screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/`; the `.txt` files are
> the primary evidence.
>
> **Helm 4 note.** This machine has Helm **v4.3.0**, newer than the v3 the course
> assumes. One flag has changed and is called out where it appears.

---

## The three words that matter

| Term | Meaning |
|---|---|
| **Chart** | the package — templates + default values (*the recipe*) |
| **Release** | one installed instance of a chart in a cluster (*the cooked meal*) |
| **Values** | the variables that customise it (*the ingredients*) |

One chart can produce many releases. That is the whole point: the Notes app below
runs as `notes-dev` and `notes-prod` **simultaneously**, from identical templates.

---

## Task 1 — Helm commands

```
$ helm version
version.BuildInfo{Version:"v4.3.0", GoVersion:"go1.27.1", KubeClientVersion:"v1.37"}
```

| Command | What it does |
|---|---|
| `helm repo add/list/update` | manage chart repositories |
| `helm search repo` | find a chart |
| `helm create` | scaffold a new chart |
| `helm lint` | validate a chart before installing |
| `helm template` | render manifests **locally**, no cluster |
| `helm install` | create a release |
| `helm list` | releases in the cluster |
| `helm status` | one release's state + resources |
| `helm get values/manifest` | what is *actually* deployed |
| `helm upgrade` | new revision |
| `helm history` | revision log |
| `helm rollback` | revert to a revision |
| `helm uninstall` | delete the release |

```
$ helm search repo bitnami/nginx
NAME                             CHART VERSION   APP VERSION   DESCRIPTION
bitnami/nginx                    25.2.1          1.31.6        NGINX Open Source is a web server...

$ helm lint /tmp/demo-chart
1 chart(s) linted, 0 chart(s) failed
```

**`helm template` is the most useful debugging command in Helm.** It renders the
chart locally and shows exactly what *would* be sent to the API server, so you can
catch a templating mistake without touching the cluster.

📄 [`logs/01-helm-commands.txt`](./logs/01-helm-commands.txt) · 📸 [`01-helm-commands.png`](./screenshots/01-helm-commands.png)

---

## Task 2 — The complete rollback workflow

`install → upgrade → verify → upgrade → verify → rollback → verify`, run end to end.

| Revision | Action | Result |
|---|---|---|
| 1 | `helm install` | nginx:1.24, 1 replica, `development` |
| 2 | `helm upgrade --set image.tag=1.26` | nginx:1.26 |
| 3 | `helm upgrade -f values-prod.yaml` | nginx:1.25, **3 replicas**, `production` |
| 4 | `helm upgrade --set image.tag=v999-does-not-exist` | **broken**, yet reported `deployed` |
| 5 | `helm rollback notes 3` | back to nginx:1.25 ×3 |
| 6 | `helm upgrade ... --atomic` (bad tag again) | **failed** |
| 7 | *automatic* rollback by `--atomic` | back to nginx:1.25 ×3 |

```
$ helm history notes
REVISION  STATUS       DESCRIPTION
1         superseded   Install complete
2         superseded   Upgrade complete
3         superseded   Upgrade complete
4         superseded   Upgrade complete
5         superseded   Rollback to 3
6         failed       Upgrade "notes" failed: resource Deployment/default/notes-deploy not ready...
7         deployed     Rollback to 5
```

**Helm never rewrites history.** A rollback *appends* a new revision whose content
equals the one you rolled back to — revision 5 is "Rollback to 3", not a deletion
of 4. The release history is an append-only audit log.

### The finding that matters: a broken upgrade still said "deployed"

```
$ helm upgrade notes ./notes-chart --set image.tag=v999-does-not-exist
STATUS: deployed                         <-- Helm is happy
REVISION: 4

$ kubectl get pods -l app=notes
notes-deploy-54f799c6f6-jh72b   1/1   Running            0   46s
notes-deploy-7868c9fdf5-7hnp4   0/1   ImagePullBackOff   0   30s
```

By default `helm upgrade` only checks that the API server **accepted** the
manifests — it does not wait for pods to become ready. A pipeline that trusts
Helm's exit code here would report a successful deploy of a release that cannot start.

### `--atomic` fixes exactly that

```
$ helm upgrade notes ./notes-chart --set image.tag=v999-does-not-exist --atomic --timeout 60s
Flag --atomic has been deprecated, use --rollback-on-failure instead
Error: UPGRADE FAILED: release notes failed, and has been rolled back due to
rollback-on-failure being set: resource Deployment/default/notes-deploy not ready

$ kubectl get deploy notes-deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
nginx:1.25                               <-- reverted automatically
```

Helm waited for readiness, saw it fail, reverted, and **exited non-zero** — which is
what makes it safe in CI.

> **Helm 4 change:** `--atomic` is deprecated in favour of **`--rollback-on-failure`**.
> The old flag still works and still prints the deprecation notice above.

📄 [`logs/02-install-upgrade-rollback.txt`](./logs/02-install-upgrade-rollback.txt) · 📸 [`part 1`](./screenshots/02-install-upgrade-rollback-part1.png) · [`part 2`](./screenshots/02-install-upgrade-rollback-part2.png)

---

## Task 3 — Mini Project: the Notes app

Chart: [`mini-project/notes-chart/`](./mini-project/notes-chart)

```
notes-chart/
├── Chart.yaml
├── values.yaml           # development: 1 replica, nginx 1.24
├── values-prod.yaml      # production:  3 replicas, nginx 1.25
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── configmap.yaml
```

**One chart, two environments** — rendered locally first, before anything is applied:

```
$ helm template notes-dev  ./notes-chart
  ENVIRONMENT: "development"      replicas: 1      image: "nginx:1.24"

$ helm template notes-prod ./notes-chart -f values-prod.yaml
  ENVIRONMENT: "production"       replicas: 3      image: "nginx:1.25"
```

Both installed side by side from the same templates:

```
$ helm list
NAME         REVISION   STATUS     CHART
notes-dev    1          deployed   notes-chart-0.1.0
notes-prod   1          deployed   notes-chart-0.1.0

$ kubectl get deploy -l 'app in (notes-dev,notes-prod)'
NAME                READY   UP-TO-DATE   AVAILABLE
notes-dev-deploy    1/1     1            1
notes-prod-deploy   3/3     3            3

$ kubectl get cm notes-dev-config  -o jsonpath='{.data}'
{"APP_NAME":"notes-app","ENVIRONMENT":"development"}
$ kubectl get cm notes-prod-config -o jsonpath='{.data}'
{"APP_NAME":"notes-app","ENVIRONMENT":"production"}
```

Both serve traffic:

```
$ kubectl exec hc -- curl -sS http://notes-dev-svc  | grep -i '<title>'
<title>Welcome to nginx!</title>
$ kubectl exec hc -- curl -sS http://notes-prod-svc | grep -i '<title>'
<title>Welcome to nginx!</title>
```

`{{ .Release.Name }}` in the templates is what keeps the two releases from
colliding — every object is named after its release, so one chart can be installed
any number of times in the same namespace. `--set service.nodePort=30091` was needed
for the second release because a NodePort is cluster-unique and the chart hardcodes
30090 as a default.

**This is the problem Helm solves.** Without it, two environments means two copies
of every manifest, kept in sync by hand. Here it is one chart plus a 6-line values
file, and the difference between environments is reviewable in a `diff`.

📄 [`logs/03-mini-project.txt`](./logs/03-mini-project.txt) · 📸 [`03-mini-project.png`](./screenshots/03-mini-project.png)

---

## Index

| Path | Contents |
|---|---|
| [`mini-project/notes-chart/`](./mini-project/notes-chart) | the Notes chart (Task 3) |
| [`09-deploying-application/guestbook-chart/`](./09-deploying-application) | course reference chart |

## Reproducing

```bash
helm lint  mini-project/notes-chart
helm install notes-dev  mini-project/notes-chart
helm install notes-prod mini-project/notes-chart \
     -f mini-project/notes-chart/values-prod.yaml --set service.nodePort=30091
helm history notes-dev
helm upgrade notes-dev mini-project/notes-chart --set image.tag=bad --rollback-on-failure --timeout 60s
helm uninstall notes-dev notes-prod
```
