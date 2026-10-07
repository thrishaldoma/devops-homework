# Session 11 — Kubernetes Services, DNS & Pod Identity

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · minikube v1.39.0 · Kubernetes v1.37.0 · **2-node cluster**

All output below is real and captured live. Full transcripts in [`logs/`](./logs),
rendered screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/`; the output is
> genuine and the `.txt` files are the primary evidence.

### Environment deviations from the assignment text

| # | Deviation | Why |
|---|---|---|
| 1 | **`minikube tunnel` not used** (Tasks 4, 12) | It creates host routing-table entries and binds privileged ports, so it needs root. Passwordless `sudo` is unavailable in this environment. `minikube service --url` and `kubectl port-forward` are used instead — both need no root and are demonstrated working. |
| 2 | **MetalLB provides the LoadBalancer's `EXTERNAL-IP`** (Task 4) | There is no cloud controller on a laptop. MetalLB fills that role, so the Service reaches a real `EXTERNAL-IP` instead of sitting at `<pending>` forever. Its layer-2 address is reachable from the node, not from macOS — same routing limitation as Task 12. |
| 3 | **`EndpointSlice` shown instead of `Endpoints`** | The `Endpoints` API is deprecated; `EndpointSlice` is what Kubernetes v1.37 actually maintains. `kubectl describe svc` still prints an `Endpoints:` line, which is included. |
| 4 | **2-node cluster** | Required to prove a NodePort answers on a node that hosts none of the app's pods (Task 3). |

---

## Task 1 — The four ports

```bash
kubectl explain pod.spec.containers.ports.containerPort
kubectl explain service.spec.ports
```

```
Client ──► nodePort 30080        opened on EVERY node (30000-32767)
              │
              ▼
           port 8080             the Service's own port, on its ClusterIP
              │
              ▼
           targetPort 80         the port on the Pod
              │
              ▼
           containerPort 80      the port the process listens on (informational)
```

All four read off one live Service:

```
port       (service VIP port) : 80
targetPort (pod port)         : 80
nodePort   (port on each node): 30080
containerPort (in the pod spec): 80
```

The crucial one is `containerPort`: it is **documentation only**. Removing it
changes nothing at runtime — what matters is that `targetPort` matches the port
the process genuinely listens on.

📄 [`logs/01-ports.txt`](./logs/01-ports.txt) · 📸 [`01-ports.png`](./screenshots/01-ports.png)

---

## Task 2 — ClusterIP (default internal networking)

Manifests: [`01-clusterip/`](./01-clusterip). `port: 8080` deliberately differs
from `targetPort: 80` so the distinction is observable.

```
NAME                    TYPE        CLUSTER-IP      PORT(S)
web-service-clusterip   ClusterIP   10.106.26.249   8080/TCP

SLICE                         PORTS   ENDPOINTS
web-service-clusterip-mghrp   80      [10.244.1.64],[10.244.0.26],[10.244.1.65]
```

Reachable three ways from inside the cluster — short name, FQDN and raw VIP:

```
$ kubectl exec curl-client -- curl -s http://web-service-clusterip:8080 | grep -i '<title>'
<title>Welcome to nginx!</title>
$ ... http://web-service-clusterip.default.svc.cluster.local:8080
<title>Welcome to nginx!</title>
$ ... http://10.106.26.249:8080
<title>Welcome to nginx!</title>
```

Note the EndpointSlice records port **80** (the pod port) while clients connect to
**8080** (the Service port) — kube-proxy performs the translation.

📄 [`logs/02-clusterip.txt`](./logs/02-clusterip.txt) · 📸 [`02-clusterip.png`](./screenshots/02-clusterip.png)

---

## Task 3 — NodePort (host-level external ingress)

Manifests: [`02-nodeport/`](./02-nodeport)

```
NAME                   TYPE       CLUSTER-IP       PORT(S)        AGE
web-service-nodeport   NodePort   10.107.181.107   80:30080/TCP   0s
```

`80:30080/TCP` reads as `<service port>:<nodePort>`.

**The nodePort is open on every node** — including one hosting no pod of this app:

```
node 192.168.49.2:30080 -> HTTP 200      (control plane)
node 192.168.49.3:30080 -> HTTP 200      (worker)
```

From the macOS host, however:

```
host -> 192.168.49.2:30080 = FAILED (unreachable)
$ minikube service web-service-nodeport --url
http://127.0.0.1:54290
host -> http://127.0.0.1:54290 = HTTP 200
```

That failure is not a misconfiguration — it is the Docker-driver limitation
analysed in Task 12.

> Both node checks initially returned connection-refused because the Service was
> only seconds old. kube-proxy must program iptables on *each* node before a
> NodePort answers; after a short wait both returned 200.

📄 [`logs/03-nodeport.txt`](./logs/03-nodeport.txt) · 📸 [`03-nodeport.png`](./screenshots/03-nodeport.png)

---

## Task 4 — LoadBalancer (cloud-native ingress simulation)

Manifests: [`03-loadbalancer/`](./03-loadbalancer)

```
NAME                       TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)
web-service-loadbalancer   LoadBalancer   10.107.135.208   192.168.49.200   80:32365/TCP
```

**LoadBalancer is a superset of the other two types.** Kubernetes allocated all
three layers automatically:

```
ClusterIP  : 10.107.135.208
nodePort   : 32365          <-- auto-assigned, never requested
port       : 80
targetPort : 80
EXTERNAL-IP: 192.168.49.200
```

The external LB simply targets that auto-created nodePort, which targets the
ClusterIP, which targets the pods. Verified from the node (MetalLB answers ARP on
the node network):

```
http://192.168.49.200 -> HTTP 200
<title>Welcome to nginx!</title>
```

Without any LB controller the `EXTERNAL-IP` column would stay `<pending>`
indefinitely — there would be nothing to answer the request for an address.

📄 [`logs/04-loadbalancer.txt`](./logs/04-loadbalancer.txt) · 📸 [`04-loadbalancer.png`](./screenshots/04-loadbalancer.png)

---

## Task 5 — ExternalName (CoreDNS CNAME alias)

Manifests: [`04-externalname/`](./04-externalname)

```
NAME                        TYPE           CLUSTER-IP   EXTERNAL-IP      PORT(S)
external-database-service   ExternalName   <none>       api.github.com   <none>

$ kubectl get endpointslice -l kubernetes.io/service-name=external-database-service
No resources found in default namespace.

external-database-service.default.svc.cluster.local  canonical name = api.github.com
```

No ClusterIP, no endpoints, no proxying — CoreDNS just returns a **CNAME**. This
is a pure DNS-layer redirect, which is why it works for any protocol but cannot
do health-checking or load balancing.

Traffic really does leave the cluster:

```
$ curl -k -H 'Host: api.github.com' https://external-database-service
HTTP 200, 2396 bytes from 20.207.73.85
{ "current_user_url": "https://api.github.com/user", ...
```

Two details worth noting. Without `-k` the handshake fails with **exit 60**: the
certificate is issued for `api.github.com`, not for the alias, so the name does
not match. And the `Host:` header is required because the alias name is otherwise
sent to GitHub, which rejects it with a 400.

📄 [`logs/05-externalname.txt`](./logs/05-externalname.txt) · 📸 [`05-externalname.png`](./screenshots/05-externalname.png)

---

## Task 6 — Headless Service (`clusterIP: None`)

Manifests: [`05-headless/`](./05-headless)

```
NAME                   TYPE        CLUSTER-IP   PORT(S)
web-service-headless   ClusterIP   None         80/TCP
```

DNS returns **one A record per pod** rather than a single VIP:

```
Name: web-service-headless.default.svc.cluster.local   Address: 10.244.0.29
Name: web-service-headless.default.svc.cluster.local   Address: 10.244.1.72
Name: web-service-headless.default.svc.cluster.local   Address: 10.244.1.73
```

And every ordinal gets a stable, individually addressable DNS name:

```
$ curl http://web-stateful-0.web-service-headless   ->  <title>web-stateful-0</title>
$ curl http://web-stateful-1.web-service-headless   ->  <title>web-stateful-1</title>
$ curl http://web-stateful-2.web-service-headless   ->  <title>web-stateful-2</title>
```

Each pod serves its own hostname, proving the requests reached three *different*
pods. This is exactly what clustered software (Kafka, Cassandra, etcd) needs:
peers must address each other **individually**, which a load-balancing VIP
actively prevents.

📄 [`logs/06-headless.txt`](./logs/06-headless.txt) · 📸 [`06-headless.png`](./screenshots/06-headless.png)

---

## Task 7 — Service without selectors (manual endpoints)

Manifests: [`07-no-selector/`](./07-no-selector)

```
$ kubectl get endpointslice -l kubernetes.io/service-name=external-legacy-db
No resources found in default namespace.          <-- no selector => K8s manages nothing

$ kubectl apply -f 07-no-selector/endpoints.yaml
SLICE                       ADDRESSES         PORT
external-legacy-db-manual   [192.168.1.150]   3306

Service ClusterIP: 10.101.0.116
Has selector    :                              <-- empty
```

Omitting the selector tells Kubernetes "I will manage the endpoints myself." The
Service still gets a ClusterIP and a DNS name, so in-cluster clients use
`external-legacy-db:3306` exactly as if it were a normal in-cluster service —
while traffic actually leaves for an external host. This is the standard way to
front a legacy database or a managed service (RDS) behind a stable internal name,
and it lets you migrate that backend later without touching a single client.

> `192.168.1.150` is illustrative and not live on this network, so the routing
> configuration is demonstrated rather than a completed TCP session.
> A modern `EndpointSlice` is used; the `Endpoints` API it replaces is deprecated.

📄 [`logs/07-no-selector.txt`](./logs/07-no-selector.txt) · 📸 [`07-no-selector.png`](./screenshots/07-no-selector.png)

---

## Task 8 — FQDN & CoreDNS deep dive

```
$ kubectl exec curl-client -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

**FQDN anatomy:** `<service>.<namespace>.svc.cluster.local`

**What `ndots:5` does.** Any name containing **fewer than 5 dots** is treated as
*relative* and gets each `search` suffix appended before being tried as-is. Short
service names resolve conveniently as a result. But `api.github.com` has only 2
dots, so it is also treated as relative:

```
api.github.com.default.svc.cluster.local   -> NXDOMAIN
api.github.com.svc.cluster.local           -> NXDOMAIN
api.github.com.cluster.local               -> NXDOMAIN
api.github.com                             -> answered (20.207.73.85)
```

Those NXDOMAIN attempts are visible in the Task 5 transcript.

**The mechanism is the solid evidence here** — those three NXDOMAIN responses are
three extra round-trips to CoreDNS before the real answer, on *every* external
lookup.

A timing comparison over 50 lookups each was also run:

| Form | real |
|---|---|
| `api.github.com` (relative) | 0.02s |
| `api.github.com.` (absolute, trailing dot) | 0.01s |

The relative form is consistently slower, but this measurement is **one run at
10ms resolution** — a single timer tick apart — so it should not be read as a
precise ratio. CoreDNS is one hop away on an idle lab cluster and caches
aggressively, which compresses the difference to near-nothing here.

The cost matters at production scale, not on this cluster: every external API call
paying up to 4 wasted round-trips adds latency and multiplies CoreDNS query
volume. Standard fixes: a trailing dot, a per-pod `dnsConfig` with `ndots: 1`, or
NodeLocal DNSCache.

📄 [`logs/08-coredns-fqdn.txt`](./logs/08-coredns-fqdn.txt) · 📸 [`08-coredns-fqdn.png`](./screenshots/08-coredns-fqdn.png)

---

## Task 9 — Pod identity: Deployment vs StatefulSet

One pod deleted from each controller, at the same time:

```
deleted: web-app-clusterip-6ccf84dc4f-mdjp6   (Deployment)
deleted: web-stateful-0                        (StatefulSet, IP 10.244.1.72)

# after
web-app-clusterip-6ccf84dc4f-4h62q   1/1   Running   13s   <-- NEW random name
web-app-clusterip-6ccf84dc4f-v2qmj   1/1   Running   4m34s
web-app-clusterip-6ccf84dc4f-wwgkk   1/1   Running   4m34s

web-stateful-0   1/1   Running   12s    <-- SAME name
web-stateful-1   1/1   Running   31s
web-stateful-2   1/1   Running   31s
```

| | Deployment | StatefulSet |
|---|---|---|
| Before | `...-mdjp6` | `web-stateful-0` |
| After | `...-4h62q` — **new identity** | `web-stateful-0` — **invariant** |

The replacement `web-stateful-0` got a **different IP** (`10.244.1.72` →
`10.244.1.74`), yet its DNS name still resolved and served correctly. That is the
practical lesson: a StatefulSet guarantees a stable *name*, never a stable IP —
so you address ordinals by DNS, never by address.

📄 [`logs/09-pod-identity.txt`](./logs/09-pod-identity.txt) · 📸 [`09-pod-identity.png`](./screenshots/09-pod-identity.png)

---

## Task 10 — Deployment vs StatefulSet vs DaemonSet

*Documentation task — no commands. Behaviours below were observed in Session 10
(Tasks 6, 7) and Session 11 (Tasks 6, 9).*

| Metric | Deployment | StatefulSet | DaemonSet |
|---|---|---|---|
| **Workload type** | Stateless microservices, web APIs | Clustered databases, distributed queues | Node-level infrastructure agents |
| **Pod naming** | Random (`<deploy>-<rs-hash>-<rand>`) | Ordinal (`<name>-0`, `-1`, `-2`) | `<ds>-<rand>`, one per node |
| **Identity** | Ephemeral, disposable | Invariant name and storage | Bound to its node |
| **Start/stop order** | Parallel, unordered | Sequential `0→1→2`, reversed on shutdown | Parallel across nodes |
| **Storage** | Shared or ephemeral `emptyDir` | One PV per ordinal via `volumeClaimTemplates` | `hostPath` / node-local |
| **Service type** | ClusterIP / NodePort / LoadBalancer | **Headless** (`clusterIP: None`) for per-pod DNS | Usually none |
| **Scaling** | Arbitrary, any node | Ordinal, at the tail | Automatic with node count |
| **Replica count** | `replicas` | `replicas` | **No field** — derived from nodes |
| **Examples** | nginx, Flask, Node.js APIs | Kafka, MongoDB, PostgreSQL, ZooKeeper | Fluentd, node-exporter, Cilium, Falco |

**Evidence from this cluster:** `mysql-0` was Ready before `mysql-1` was created
(sequential); `data-mysql-0` and `data-mysql-1` bound to separate 1Gi PVs
(per-ordinal storage); `node-exporter` reported `DESIRED 2` without any `replicas`
field (node-derived).

---

## Task 11 — Cost optimisation & service selection

*Documentation task — no commands.*

### The LoadBalancer-per-service anti-pattern

Each `type: LoadBalancer` provisions a **billable cloud load balancer**
(~$18–25/month on AWS/GCP/Azure, plus data processing charges):

```
ANTI-PATTERN                              BEST PRACTICE
Service A ─► NLB 1  ($25/mo)              Internet ─► 1 LB ($25/mo)
Service B ─► NLB 2  ($25/mo)                            │
Service C ─► NLB 3  ($25/mo)                   [ NGINX Ingress Controller ]
    ...                                          │        │        │
50 services = $1,250 / month               ClusterIP A   B        C
                                           50 services = $25 / month
```

**Saving: ~$1,225/month**, and one LB means one place for TLS certificates, WAF
rules and access logs. The Ingress Controller multiplexes by hostname and path at
L7 — exactly what Session 12 demonstrates.

The trade-off is real: the single LB becomes a shared failure domain and a
bandwidth chokepoint, so the controller is run with multiple replicas. Ingress is
also **HTTP/HTTPS-only** — raw TCP/UDP (a database, a game server) still needs its
own LoadBalancer.

### Service selection decision tree

```
Need to expose this outside the cluster?
│
├── NO ──► Do pods need to address each other individually (Kafka/DB peers)?
│           ├── YES ──► HEADLESS SERVICE (clusterIP: None)
│           └── NO  ──► CLUSTERIP  (the default)
│
└── YES ─► Is the target actually an external 3rd-party host (RDS, Stripe)?
            ├── YES ──► EXTERNALNAME  (DNS CNAME, no proxying)
            └── NO  ──► On a public cloud?
                         ├── YES, HTTP/HTTPS ──► ONE INGRESS behind ONE LoadBalancer,
                         │                       apps stay internal ClusterIP
                         ├── YES, raw TCP/UDP ──► LOADBALANCER per service
                         └── NO (on-prem / dev) ──► NODEPORT
```

---

## Task 12 — Minikube Docker-driver port-binding gotcha

**Root cause.** minikube's "node" is a Docker container on an internal bridge:

```
$ minikube ip
192.168.49.2
$ docker network inspect minikube --format '...'
subnet: 192.168.49.0/24 gateway: 192.168.49.1
$ docker ps --filter name=minikube --format 'table {{.Names}}\t{{.Ports}}'
NAMES          PORTS
minikube       127.0.0.1:52419->22/tcp, 127.0.0.1:52418->8443/tcp, ...
minikube-m02   127.0.0.1:52459->22/tcp, 127.0.0.1:52462->8443/tcp, ...
```

Note what is **absent**: port 30080 is not published to the host at all. Only ssh
and the API server are mapped, and only on `127.0.0.1`.

On Linux the Docker bridge lives in the host's own kernel, so the host can route
to `192.168.49.0/24` directly. On **macOS**, Docker Desktop runs the engine inside
its own lightweight VM, so that subnet exists only inside that VM. The macOS
network stack has no route to it:

```
$ netstat -rn -f inet | grep -c '192.168.49'
host routes to 192.168.49.0/24: 0
```

**Proof — the same port, two vantage points:**

```
IN-CLUSTER  192.168.49.2:30080 -> HTTP 200
FROM HOST   192.168.49.2:30080 -> no route / connection failed
```

The NodePort works perfectly. It is the *host's* reachability that is missing.

### Workarounds (both verified, neither needs root)

| | Command | Result |
|---|---|---|
| 1 | `minikube service web-service-nodeport --url` → `http://127.0.0.1:54465` | **HTTP 200** |
| 2 | `kubectl port-forward svc/web-service-nodeport 18081:80` | **HTTP 200** |
| 3 | `minikube tunnel` | **not run** — needs root; passwordless sudo unavailable here |

Workaround 1 opens an ephemeral loopback listener proxying into the Docker
network. Workaround 2 tunnels over the Kubernetes API connection, bypassing node
networking entirely — but it targets **one pod**, so it does not load-balance
(which is why Session 10's traffic-split tasks used in-cluster curl instead).

📄 [`logs/12-minikube-gotcha.txt`](./logs/12-minikube-gotcha.txt) · 📸 [`12-minikube-gotcha.png`](./screenshots/12-minikube-gotcha.png)

---

## Manifest index

| Path | Service type |
|---|---|
| [`01-clusterip/`](./01-clusterip) | ClusterIP + client pod |
| [`02-nodeport/`](./02-nodeport) | NodePort (30080) |
| [`03-loadbalancer/`](./03-loadbalancer) | LoadBalancer |
| [`04-externalname/`](./04-externalname) | ExternalName |
| [`05-headless/`](./05-headless) | Headless + StatefulSet |
| [`07-no-selector/`](./07-no-selector) | Service with manual EndpointSlice |
