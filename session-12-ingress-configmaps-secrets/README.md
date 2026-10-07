# Session 12 — Ingress, ConfigMaps & Secrets

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · minikube v1.39.0 · Kubernetes v1.37.0 · ingress-nginx v1.15.1

All output is real and captured live. Transcripts in [`logs/`](./logs), rendered
screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/`; the output is
> genuine and the `.txt` files are the primary evidence.

### Environment deviations from the assignment text

| # | Deviation | Why |
|---|---|---|
| 1 | **`/etc/hosts` not modified** (Task 9) | Requires `sudo`, unavailable here. And per Session 11 Task 12, macOS cannot route to `192.168.49.0/24` anyway, so the entry alone would not have worked. |
| 2 | Ingress reached via **`kubectl port-forward` + `Host:` header / `curl --resolve`** | Functionally identical: the Ingress controller routes on the **Host header**, which is precisely what an `/etc/hosts` entry would cause the client to send. Both matching and non-matching hosts are tested to prove routing really happens. |
| 3 | TLS private key kept **out of the repository** | `tls.key` and `tls.crt` are generated into a scratch directory. A private key must never be committed, even a throwaway self-signed one. The exact `openssl` command is documented so it is fully reproducible. |

---

## Task 1 — Non-sensitive configuration via ConfigMaps

Manifest: [`01-configmap/app-config.yaml`](./01-configmap/app-config.yaml)

```
$ kubectl describe configmap yatri-app-config
Data
====
DEFAULT_CURRENCY:   INR
ENVIRONMENT:        production
LOG_LEVEL:          INFO
MAX_BOOKING_DAYS:   90
PORT:               8080

$ kubectl get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}'
production
```

The point is decoupling: the same immutable container image runs in dev, staging
and production by swapping this object. Nothing environment-specific is baked
into the image.

📄 [`logs/01-configmap.txt`](./logs/01-configmap.txt) · 📸 [`01-configmap.png`](./screenshots/01-configmap.png)

---

## Task 2 — ConfigMap live update & pod immobility

The important lesson of the session:

```
$ kubectl patch configmap yatri-app-config --type merge -p '{"data":{"ENVIRONMENT":"staging"}}'
configmap/yatri-app-config patched
ConfigMap now says: staging

$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=production            <-- the RUNNING pod did NOT change

$ kubectl rollout restart deployment/yatri-backend
$ kubectl exec deploy/yatri-backend -- env | grep ENVIRONMENT
ENVIRONMENT=staging               <-- new pods picked it up
```

**Why.** Environment variables are resolved **once**, when the container starts,
and are then part of the process's immutable environment. Patching the ConfigMap
updates the API object but cannot reach into a running process. `kubectl rollout
restart` creates new pods — which re-read the ConfigMap — using the normal rolling
strategy, so it is zero-downtime.

> A ConfigMap mounted as a **volume** behaves differently: the kubelet does
> eventually refresh the files on disk. Only `env`/`envFrom` injection is frozen
> at start. Reverted to `production` afterwards for the remaining tasks.

📄 [`logs/02-configmap-live-update.txt`](./logs/02-configmap-live-update.txt) · 📸 [`02-configmap-live-update.png`](./screenshots/02-configmap-live-update.png)

---

## Task 3 — Secrets & base64 mechanics

Manifest: [`02-secret/db-secret.yaml`](./02-secret/db-secret.yaml)

```
$ kubectl describe secret yatri-db-secret
Data
====
POSTGRES_PASSWORD:  14 bytes         <-- masked; only the length is shown
POSTGRES_USER:      11 bytes

$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode
secretpassword
$ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_USER}' | base64 --decode
yatri_admin
```

`kubectl describe` masks the values, which makes Secrets *look* protected. They
are not. **Base64 is encoding, not encryption** — a one-line command recovers the
plaintext. A Secret's real protections are RBAC, encryption-at-rest configured on
etcd, and not committing it to Git. The 14-byte length is itself a useful signal
— see Task 4.

📄 [`logs/03-secret.txt`](./logs/03-secret.txt) · 📸 [`03-secret.png`](./screenshots/03-secret.png)

---

## Task 4 — The trailing-newline gotcha

```
$ echo 'secretpassword' | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.
                                             ^^ the invisible newline
$ echo 'secretpassword' | base64
c2VjcmV0cGFzc3dvcmQK

$ echo -n 'secretpassword' | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
$ echo -n 'secretpassword' | base64
c2VjcmV0cGFzc3dvcmQ=

wrong  -> byte length: 15
right  -> byte length: 14
```

`echo` appends `0x0A`. The database therefore receives `secretpassword\n`
(15 bytes) and rejects the login, while every log, dashboard and `kubectl
describe` shows something that *looks* correct.

**Two reliable tells:** the base64 of a newline-terminated string ends in **`K`**;
the clean one ends in **`=`** padding. And `kubectl describe secret` shows a byte
count one larger than the password's real length. Our committed secret is
`c2VjcmV0cGFzc3dvcmQ=` — 14 bytes, correct.

Safest habit: let `kubectl` do the encoding — `kubectl create secret generic ...
--from-literal=POSTGRES_PASSWORD=secretpassword` never introduces a newline.

📄 [`logs/04-newline-gotcha.txt`](./logs/04-newline-gotcha.txt) · 📸 [`04-newline-gotcha.png`](./screenshots/04-newline-gotcha.png)

---

## Task 5 — Enterprise secret management

*Primarily a documentation task; the cluster check is included.*

```
$ kubectl get crds | grep -i -E 'secret|vault'
Standard native Kubernetes Secrets in use (no external secret operator CRDs)
$ kubectl auth can-i get secrets
yes
```

### The vulnerability

Committing a Secret manifest to Git means:
- **Git history is forever.** Deleting the file in a later commit does not remove it; the value must be treated as compromised and rotated.
- **Everyone with repo read access has production credentials**, which is a far wider audience than those with cluster RBAC.
- **No rotation story.** The value is pinned to a commit; rotating means a code change, review and redeploy.
- Base64 offers **zero** protection, as Task 3 demonstrated.

### The production pattern

```
AWS Secrets Manager / Azure Key Vault / HashiCorp Vault   (source of truth)
                     │
                     │  External Secrets Operator (ESO) or Vault Agent Injector
                     │  authenticates via the pod's ServiceAccount (IRSA / K8s auth)
                     ▼
        Kubernetes Secret, created in-cluster at runtime
                     │
                     ▼
              Pod  (env var or mounted volume)
```

The repository stores only an `ExternalSecret` **reference** — which key to fetch
from which store — never the value. The operator reconciles it on a TTL, so
rotating the secret upstream propagates automatically.

### CI/CD integration

GitHub Actions secrets and Azure DevOps Variable Groups inject credentials as
masked environment variables at deploy time. The manifest in Git holds a
placeholder substituted during the pipeline run, so the plaintext exists only in
the runner's memory for the duration of the job. Layer on: `kubeseal`
(SealedSecrets) for GitOps repos, etcd encryption-at-rest, tight RBAC on
`get secrets`, and scanning (gitleaks / trufflehog) to catch leaks before merge.

📄 [`logs/05-enterprise-secrets.txt`](./logs/05-enterprise-secrets.txt) · 📸 [`05-enterprise-secrets.png`](./screenshots/05-enterprise-secrets.png)

---

## Task 6 — Combined ConfigMap + Secret injection

Manifest: [`04-full-demo/backend.yaml`](./04-full-demo/backend.yaml) — uses both
injection styles at once:

```yaml
envFrom:                      # BULK: every key in the ConfigMap
  - configMapRef:
      name: yatri-app-config
env:                          # GRANULAR: named keys from the Secret
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: yatri-db-secret
        key: POSTGRES_PASSWORD
```

```
$ kubectl exec deploy/yatri-backend -- env | grep -E 'ENVIRONMENT|LOG_LEVEL|POSTGRES|CURRENCY'
DEFAULT_CURRENCY=INR
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_BOOKING_DAYS=90
PORT=8080
POSTGRES_PASSWORD=secretpassword
POSTGRES_USER=yatri_admin
```

And the application reads them at request time:

```
$ curl http://yatri-backend-service:8080/
Yatri Backend API
path: /
--------------------------------
ENVIRONMENT: production
LOG_LEVEL: INFO
POSTGRES_USER: yatri_admin
POSTGRES_PASSWORD: secretpassword
```

`envFrom` is convenient but imports *everything* and gives no control over names;
`secretKeyRef` is explicit and lets you rename a key. The usual convention is
exactly this split: bulk for config, granular for credentials.

📄 [`logs/06-combined-injection.txt`](./logs/06-combined-injection.txt) · 📸 [`06-combined-injection.png`](./screenshots/06-combined-injection.png)

---

## Task 7 — Ingress Resource vs Ingress Controller

| | **Ingress Resource** | **Ingress Controller** |
|---|---|---|
| What it is | A Kubernetes API object — YAML | A running pod: a real reverse proxy |
| Contains | Hosts, paths, TLS refs, backend services | nginx / Envoy / HAProxy / Traefik |
| Does it route traffic? | **No.** It is inert data | **Yes.** It terminates and forwards connections |
| Lifecycle | Stored in etcd | Watches the API, regenerates config, reloads |
| If the other is missing | Rules exist, nothing happens | Proxy runs with no rules |

```
$ kubectl api-resources | grep -i ingress
ingressclasses     networking.k8s.io/v1   false   IngressClass
ingresses    ing   networking.k8s.io/v1   true    Ingress

$ kubectl get deploy -n ingress-nginx
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
ingress-nginx-controller   1/1     1            1           49m
```

**Proof of the relationship** — our Ingress objects were compiled into the
controller's live `nginx.conf`:

```
$ kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- grep 'server_name' /etc/nginx/nginx.conf
        server_name "api.campus.local" ;
        server_name "portal.campus.local" ;
        server_name "yatri.local" ;

        set $ingress_name   "campus-ingress-tls";
        set $ingress_name   "yatri-ingress";
```

The controller's control loop read our declarative YAML and wrote imperative nginx
configuration. That translation *is* the Ingress Controller's entire job.

📄 [`logs/07-ingress-resource-vs-controller.txt`](./logs/07-ingress-resource-vs-controller.txt) · 📸 [`07-ingress-resource-vs-controller.png`](./screenshots/07-ingress-resource-vs-controller.png)

---

## Task 8 — NGINX Ingress Controller activation

```
$ minikube addons enable ingress
* The 'ingress' addon is enabled

$ kubectl get pods -n ingress-nginx
NAME                                       READY   STATUS      RESTARTS      AGE
ingress-nginx-admission-create-vldwt       0/1     Completed   0             47m
ingress-nginx-admission-patch-w9qlj        0/1     Completed   0             47m
ingress-nginx-controller-d7cd8c989-dgdc8   1/1     Running     1 (41m ago)   47m

$ kubectl wait --namespace ingress-nginx --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=180s
pod/ingress-nginx-controller-d7cd8c989-dgdc8 condition met

NAME                       CLASS   CONTROLLER             AGE
nginx (default)            nginx   k8s.io/ingress-nginx   47m
```

The two `Completed` jobs are the admission-webhook certificate bootstrap — they
run once and exit, which is why `0/1` here is healthy rather than broken.

📄 [`logs/08-ingress-controller.txt`](./logs/08-ingress-controller.txt) · 📸 [`08-ingress-controller.png`](./screenshots/08-ingress-controller.png)

---

## Task 9 — Local DNS resolution

```
$ minikube ip
192.168.49.2
$ grep -E 'yatri.local|campus.local' /etc/hosts
(no entry present - sudo unavailable)
```

On a Linux workstation you would add:

```
192.168.49.2  yatri.local portal.campus.local api.campus.local
```

Two reasons that is not used here: editing `/etc/hosts` needs `sudo`, and (Session
11, Task 12) macOS cannot route to `192.168.49.0/24` at all, so the mapping would
resolve to an unreachable address.

**The equivalent used throughout this session:**

```bash
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80
curl -H 'Host: yatri.local' http://127.0.0.1:18080/
```

An `/etc/hosts` entry only changes which IP the client dials; the HTTP request it
sends still carries `Host: yatri.local`, and that header is the *only* thing the
Ingress controller routes on. Sending it explicitly exercises the identical path.

📄 [`logs/09-local-dns.txt`](./logs/09-local-dns.txt) · 📸 [`09-local-dns.png`](./screenshots/09-local-dns.png)

---

## Task 10 — Layer 7 path-based routing

Manifest: [`04-full-demo/ingress.yaml`](./04-full-demo/ingress.yaml)

```
$ kubectl describe ingress yatri-ingress
Rules:
  Host         Path            Backends
  yatri.local
               /api(/|$)(.*)   yatri-backend-service:8080  (10.244.1.78:8080,10.244.0.34:8080)
               /               yatri-frontend-service:80   (10.244.0.32:80,10.244.1.76:80)
Annotations:   nginx.ingress.kubernetes.io/rewrite-target: /$2
```

One hostname, two microservices:

```
$ curl -H 'Host: yatri.local' http://127.0.0.1:18080/ | grep -i '<title>'
<title>Welcome to nginx!</title>                     <-- frontend

$ curl -H 'Host: yatri.local' http://127.0.0.1:18080/api/
Yatri Backend API
ENVIRONMENT: production
POSTGRES_USER: yatri_admin                           <-- backend
```

**The rewrite proven, not just configured.** The backend echoes the path it
actually received:

```
$ curl -H 'Host: yatri.local' http://127.0.0.1:18080/api/bookings | grep '^path:'
path: /bookings
```

The client asked for `/api/bookings`; the backend saw `/bookings`. The regex
`/api(/|$)(.*)` captures everything after `/api` as group 2, and
`rewrite-target: /$2` forwards only that — so the backend needs no knowledge of
the `/api` prefix it is mounted under.

Routing is host-scoped — an unmatched host is not served:

```
Host: unknown.local -> HTTP 404
Host: yatri.local   -> HTTP 200
```

📄 [`logs/10-path-routing.txt`](./logs/10-path-routing.txt) · 📸 [`10-path-routing.png`](./screenshots/10-path-routing.png)

---

## Task 11 — Virtual host-based routing

Manifest: [`03-ingress/ingress-tls.yaml`](./03-ingress/ingress-tls.yaml)

```
NAME                 CLASS   HOSTS                                  ADDRESS        PORTS
campus-ingress-tls   nginx   portal.campus.local,api.campus.local   192.168.49.2   80, 443
```

Two hostnames, one controller, one IP — separated purely by the Host header:

```
$ curl -sk https://portal.campus.local/ | grep -i '<title>'
<title>Welcome to nginx!</title>                 -> yatri-frontend-service

$ curl -sk https://api.campus.local/api/
Yatri Backend API
ENVIRONMENT: production                          -> yatri-backend-service
```

Because these hosts have TLS configured, plain HTTP is redirected automatically:

```
http portal.campus.local -> HTTP 308 (redirect to https://portal.campus.local/)
```

ingress-nginx enables `ssl-redirect` by default for any host with a TLS block —
HTTPS is opt-out, not opt-in.

📄 [`logs/11-host-routing.txt`](./logs/11-host-routing.txt) · 📸 [`11-host-routing.png`](./screenshots/11-host-routing.png)

---

## Task 12 — Hybrid routing (host + path in one resource)

`campus-ingress-tls` combines both dimensions: `portal.campus.local` routes by
host only, while `api.campus.local` additionally routes by path.

```
$ kubectl describe ingress campus-ingress-tls
Rules:
  Host                 Path            Backends
  portal.campus.local
                       /               yatri-frontend-service:80
  api.campus.local
                       /api(/|$)(.*)   yatri-backend-service:8080
                       /               yatri-backend-service:8080
```

Every host+path combination verified:

```
portal.campus.local/         -> HTTP 200
api.campus.local/api/health  -> backend saw path: /health      (prefix rewritten)
api.campus.local/            -> backend saw path: /            (no rewrite needed)
```

nginx matches the **host first**, then the longest/most specific path within that
host's server block — which is why `/api/health` hits the regex rule rather than
the `/` prefix rule.

📄 [`logs/12-hybrid-routing.txt`](./logs/12-hybrid-routing.txt) · 📸 [`12-hybrid-routing.png`](./screenshots/12-hybrid-routing.png)

---

## Task 13 — TLS/HTTPS termination

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=campus.local/O=CampusDevOps" \
  -addext "subjectAltName=DNS:campus.local,DNS:portal.campus.local,DNS:api.campus.local"

kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
```

```
subject= /CN=campus.local/O=CampusDevOps
notBefore=Sep 18 06:53:39 2026 GMT
notAfter=Sep 18 06:53:39 2027 GMT
X509v3 Subject Alternative Name:
    DNS:campus.local, DNS:portal.campus.local, DNS:api.campus.local

NAME              TYPE                DATA   AGE
campus-tls-cert   kubernetes.io/tls   2      0s
tls.crt:  1147 bytes
tls.key:  1704 bytes
```

**Handshake verified on port 443:**

```
$ curl -kv --resolve portal.campus.local:443:127.0.0.1 https://portal.campus.local/
* SSL connection using TLSv1.3 / AEAD-AES256-GCM-SHA384
*  subject: CN=campus.local; O=CampusDevOps
*  issuer: CN=campus.local; O=CampusDevOps
< HTTP/2 200
<title>Welcome to nginx!</title>
```

TLS is **terminated at the Ingress controller**: it decrypts, then forwards plain
HTTP to the backend Service over the pod network. The application never handles
certificates — that is the operational win, since renewal happens in one place.

`subject == issuer` is the definition of self-signed, which is why `-k` is
required; a real deployment uses cert-manager with Let's Encrypt. Note also that
`kubernetes.io/tls` is a *typed* Secret: Kubernetes requires exactly the keys
`tls.crt` and `tls.key`.

> The `.crt`/`.key` files are generated outside the repository and are not
> committed — a private key must never be checked in, even a throwaway one.

📄 [`logs/13-ingress-tls.txt`](./logs/13-ingress-tls.txt) · 📸 [`13-ingress-tls.png`](./screenshots/13-ingress-tls.png)

---

## Task 14 — End-to-end integration & automation

[`04-full-demo/run-demo.sh`](./04-full-demo/run-demo.sh) applies the whole stack
in dependency order; [`cleanup.sh`](./04-full-demo/cleanup.sh) reverses it.

```
$ bash 04-full-demo/run-demo.sh
==> 1/5 ConfigMap        ==> 2/5 Secret        ==> 3/5 Backend
==> 4/5 Frontend         ==> 5/5 Ingress
deployment "yatri-backend" successfully rolled out
deployment "yatri-frontend" successfully rolled out
```

Because every object carries `app: yatri-app`, the entire stack audits in one
command:

```
$ kubectl get configmap,secret,ingress,deploy,svc -l app=yatri-app
configmap/yatri-app-config    5      configmap/yatri-backend-src   1
secret/yatri-db-secret        Opaque secret/campus-tls-cert        kubernetes.io/tls
ingress/yatri-ingress         ingress/campus-ingress-tls
deployment/yatri-backend  2/2  deployment/yatri-frontend  2/2
service/yatri-backend-service  service/yatri-frontend-service
```

Teardown, then confirmation of a clean namespace:

```
$ bash 04-full-demo/cleanup.sh
==> deleting ingress.yaml ... configmap.yaml
$ kubectl get deploy,svc,ingress -l app=yatri-app
No resources found in default namespace.
```

**Multi-document YAML.** `backend.yaml` holds three objects — a ConfigMap carrying
the Python source, a Deployment and a Service — separated by `---`. `kubectl
apply` processes them in order, so co-locating one component's objects keeps them
reviewable and deletable as a unit.

**Ordering matters.** The ConfigMap and Secret are applied *before* the
Deployment that references them. Kubernetes would otherwise create the pods and
leave them in `CreateContainerConfigError` until the missing object appeared.
`cleanup.sh` deletes in reverse and uses `--ignore-not-found`, making re-runs
idempotent.

📄 [`logs/14-full-demo.txt`](./logs/14-full-demo.txt) · 📸 [`14-full-demo.png`](./screenshots/14-full-demo.png)

---

## Manifest index

| Path | Contents |
|---|---|
| [`01-configmap/`](./01-configmap) | `yatri-app-config` (Task 1) |
| [`02-secret/`](./02-secret) | `yatri-db-secret` (Tasks 3–4) |
| [`03-ingress/`](./03-ingress) | `campus-ingress-tls` — hybrid routing + TLS (Tasks 11–13) |
| [`04-full-demo/`](./04-full-demo) | Backend, frontend, ingress, `run-demo.sh`, `cleanup.sh` (Tasks 6, 10, 14) |

## Reproducing this session

```bash
minikube addons enable ingress
kubectl wait -n ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
bash 04-full-demo/run-demo.sh
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 18080:80 &
curl -H 'Host: yatri.local' http://127.0.0.1:18080/api/
bash 04-full-demo/cleanup.sh
```
