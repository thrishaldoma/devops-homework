# Session 10 — Kubernetes Core Objects, Controllers & Deployment Strategies

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · minikube v1.39.0 · Kubernetes v1.37.0 · containerd 2.3.4 · **2-node cluster**

Every command below was executed against a live cluster. The blocks marked
**Output** are real captured output; full transcripts are in [`logs/`](./logs)
and the matching rendered screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/`. The output is
> genuine; only the presentation is generated. The `.txt` files are the primary evidence.

### Environment deviations from the assignment text

These are deliberate, and each is justified where it appears:

| # | Deviation | Why |
|---|---|---|
| 1 | **2-node cluster** (`--nodes=2`) | A DaemonSet running "one pod per node" and cross-node NodePort routing are not demonstrable on a single node. |
| 2 | Traffic tests for Tasks 11–13 run **from inside the cluster** (a `curl-client` pod) instead of `curl http://localhost:3002x` | `$(minikube ip)` is not routable from macOS with the Docker driver (analysed in Session 11, Task 12). More importantly, `kubectl port-forward` pins a **single pod**, which would have shown 100% of one version and destroyed the whole point of the canary split. In-cluster requests go through the Service VIP and are load-balanced by kube-proxy, so the measured ratios are real. |
| 3 | Service-selector flips are **gated on observed endpoints** before curling | The API updates a Service instantly, but kube-proxy needs ~1–2s to reprogram iptables on every node. Curling immediately returns the *old* backend. See Task 11. |

---

## Task 1 — Cluster health verification

```bash
kubectl version --output=yaml
kubectl cluster-info
kubectl get nodes -o wide
```

**Output**

```
Kubernetes control plane is running at https://127.0.0.1:52418
CoreDNS is running at https://127.0.0.1:52418/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

NAME           STATUS   ROLES           AGE     VERSION   INTERNAL-IP    CONTAINER-RUNTIME
minikube       Ready    control-plane   8m59s   v1.37.0   192.168.49.2   containerd://2.3.4
minikube-m02   Ready    <none>          8m44s   v1.37.0   192.168.49.3   containerd://2.3.4
```

📄 [`logs/01-cluster-health.txt`](./logs/01-cluster-health.txt) · 📸 [`01-cluster-health.png`](./screenshots/01-cluster-health.png)

---

## Task 2 — Standard Pod deployment, inspection & teardown

Manifest: [`pod.yml`](./pod.yml) — shows the four mandatory top-level fields
(`apiVersion`, `kind`, `metadata`, `spec`).

```bash
kubectl apply -f pod.yml
kubectl get pods -o wide
kubectl logs nginx-pod
kubectl delete -f pod.yml
```

**Output**

```
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE
nginx-pod   1/1     Running   0          0s    10.244.1.2   minikube-m02
```

The scheduler placed the pod on the **worker** node, not the control plane — the
scheduling decision from Session 9's Task 5 walkthrough, visible in practice.

📄 [`logs/02-nginx-pod-operations.txt`](./logs/02-nginx-pod-operations.txt) · 📸 [`02-nginx-pod-operations.png`](./screenshots/02-nginx-pod-operations.png)

---

## Task 3 — Error state simulation: `ErrImagePull` → `ImagePullBackOff`

Manifest: [`pod-lifecycle/06-imagepullbackoff.yaml`](./pod-lifecycle/06-imagepullbackoff.yaml)

**Output** — both states captured, 12s apart:

```
NAME                    READY   STATUS         RESTARTS   AGE
lifecycle-image-error   0/1     ErrImagePull   0          12s

NAME                    READY   STATUS             RESTARTS   AGE
lifecycle-image-error   0/1     ImagePullBackOff   0          32s

  Normal   Scheduled  Successfully assigned default/lifecycle-image-error to minikube-m02
  Warning  Failed     Failed to pull image "nginx:this-tag-does-not-exist-9999": ... not found
  Normal   BackOff    Back-off pulling image "nginx:this-tag-does-not-exist-9999"
```

**Why the API object succeeds while the container fails.** These are two separate
stages. `kubectl apply` only has to satisfy the **API server**: the YAML is valid,
so the Pod object is admitted and persisted in `etcd`. Nothing has tried to pull
an image yet. The *runtime* failure happens later and elsewhere — the scheduler
assigns the pod to `minikube-m02`, that node's kubelet asks containerd to pull the
tag, and the registry returns `not found`. The object therefore exists and is
queryable; only its `status` reports the problem. `ErrImagePull` is the first
failure; after it repeats, the kubelet switches to `ImagePullBackOff` and retries
on an exponential backoff instead of hammering the registry.

📄 [`logs/03-imagepullbackoff-error.txt`](./logs/03-imagepullbackoff-error.txt) · 📸 [`03-imagepullbackoff-error.png`](./screenshots/03-imagepullbackoff-error.png)

---

## Task 4 — Capturing transient Pod lifecycle stages

Manifest: [`hello.yml`](./hello.yml) — `busybox` with `restartPolicy: Never`.

Polled every 0.3s (consecutive duplicates removed) to catch all three stages:

```
hello-pod  0/1  ContainerCreating
hello-pod  1/1  Running
hello-pod  0/1  Completed

$ kubectl get pod hello-pod -o jsonpath='{.status.phase}'
Succeeded
Container exit code: 0
```

`Completed` in the STATUS column corresponds to the pod **phase** `Succeeded`.
`restartPolicy: Never` is what allows the pod to settle there — with the default
`Always` it would be restarted forever and become `CrashLoopBackOff` even on a
clean exit.

📄 [`logs/04-pod-lifecycle-stages.txt`](./logs/04-pod-lifecycle-stages.txt) · 📸 [`04-pod-lifecycle-stages.png`](./screenshots/04-pod-lifecycle-stages.png)

---

## Task 5 — Exhaustive pod lifecycle & probes lab

All 12 manifests in [`pod-lifecycle/`](./pod-lifecycle) were applied and observed.

| # | Manifest | Observed result |
|---|---|---|
| 01 | `01-running.yaml` | phase `Running` |
| 02 | `02-pending.yaml` | `Pending` — `0/2 nodes are available: 2 Insufficient cpu, 2 Insufficient memory` |
| 03 | `03-succeeded.yaml` | `Completed`, phase `Succeeded`, exit 0 |
| 04 | `04-failed.yaml` | `Error`, phase `Failed`, exit 1 |
| 05 | `05-crashloopbackoff.yaml` | `ContainerCreating → Error ×3 → CrashLoopBackOff` |
| 06 | `06-imagepullbackoff.yaml` | see Task 3 |
| 07 | `07-readiness.yaml` | `0/1 Running` for ~25s, then `1/1 Running` |
| 08 | `08-liveness.yaml` | `RESTARTS 0 → 1` after the probe failed 3× |
| 09 | `09-startup.yaml` | 30s boot, `RESTARTS` stayed **0** |
| 10 | `10-init-container.yaml` | `Init:0/1 → Running` |
| 11 | `11-multi-container.yaml` | `READY 2/2`, sidecar tailing the app's log |
| 12 | `12-termination.yaml` | delete took **11.45s**, not instant |

**Key observations**

*Pending* — the object is created but unschedulable. The scheduler reports exactly
why, per node:

```
Warning  FailedScheduling  0/2 nodes are available: 2 Insufficient cpu, 2 Insufficient memory.
```

*CrashLoopBackOff* — note the STATUS column is `Error` immediately after each exit
and only becomes `CrashLoopBackOff` during the backoff *wait*:

```
lifecycle-crashloop  0/1  ContainerCreating  restarts=0
lifecycle-crashloop  0/1  Error              restarts=0
lifecycle-crashloop  0/1  Error              restarts=3
lifecycle-crashloop  0/1  CrashLoopBackOff   restarts=3
```

*Readiness ≠ Running* — the container ran the entire time, but stayed out of
Service endpoints until `/tmp/ready` appeared:

```
lifecycle-readiness  READY=0/1  Running
lifecycle-readiness  READY=1/1  Running
```

*Liveness self-healing* — the kubelet restarted the container by itself:

```
Warning  Unhealthy  Liveness probe failed: cat: can't open '/tmp/healthy'
Normal   Killing    Container app failed liveness probe, will be restarted
```

*Startup probe* — the same 30s delay with **no** restart, because the startup
probe suspends liveness until it first succeeds (`failureThreshold: 30`,
`periodSeconds: 5` → up to 150s of grace).

*Graceful termination* — `time kubectl delete` measured **11.45s total** against a
`terminationGracePeriodSeconds: 30`, proving the `SIGTERM` trap ran its 10s
cleanup before exiting rather than being killed instantly.

📄 [`logs/05-lifecycle-probes-crashloop.txt`](./logs/05-lifecycle-probes-crashloop.txt) · 📸 [`05-lifecycle-probes-crashloop.png`](./screenshots/05-lifecycle-probes-crashloop.png)
📄 [`logs/05-lifecycle-init-multicontainer.txt`](./logs/05-lifecycle-init-multicontainer.txt) · 📸 [`05-lifecycle-init-multicontainer.png`](./screenshots/05-lifecycle-init-multicontainer.png)

---

## Task 6 — ReplicaSet & StatefulSet

### Part A — ReplicaSet self-healing ([`replicaset.yml`](./replicaset.yml))

```
$ kubectl delete pod nginx-rs-f9wsx
NAME             READY   STATUS    RESTARTS   AGE
nginx-rs-fmsfp   1/1     Running   0          3s
nginx-rs-jcn6r   1/1     Running   0          3s
nginx-rs-mj7qg   1/1     Running   0          2s      <-- brand-new replacement
```

`f9wsx` was deleted; `mj7qg` appeared within ~1s. The ReplicaSet controller's
reconciliation loop saw 2 pods where the spec says 3 and created one.

### Part B — StatefulSet ([`k8s-core-objects/statefulset.yml`](./k8s-core-objects/statefulset.yml))

```
mysql-0 0/1 ContainerCreating |
mysql-0 1/1 Running | mysql-1 0/1 ContainerCreating |
mysql-0 1/1 Running | mysql-1 1/1 Running |

NAME           STATUS   VOLUME                                     CAPACITY   STORAGECLASS
data-mysql-0   Bound    pvc-73fad1b2-f535-4976-adeb-d3e913358ed8   1Gi        standard
data-mysql-1   Bound    pvc-efd8fe66-61a2-41a1-8026-00d605b4874c   1Gi        standard
```

Three StatefulSet properties visible at once: **ordinal names** (`mysql-0`,
`mysql-1`), **strict ordering** (`mysql-0` is Ready before `mysql-1` is even
created), and **one PVC per ordinal** from `volumeClaimTemplates`. Deleting
`mysql-0` brought back a pod with the *same name*.

> The manifest sets `MYSQL_ROOT_PASSWORD`. Without it (or
> `MYSQL_ALLOW_EMPTY_PASSWORD`) the official image exits immediately and the pod
> CrashLoops, so the PVC binding could never be demonstrated.

📄 [`logs/06-controllers-rs-statefulset.txt`](./logs/06-controllers-rs-statefulset.txt) · 📸 [`06-controllers-rs-statefulset.png`](./screenshots/06-controllers-rs-statefulset.png)

---

## Task 7 — DaemonSet: one pod per node

Manifest: [`k8s-core-objects/deamonset.yml`](./k8s-core-objects/deamonset.yml)
(also at [`daemonset/node-agent-ds.yaml`](./daemonset/node-agent-ds.yaml))

```
NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
node-exporter   2         2         2       2            2           <none>

node-exporter-46q2x   minikube
node-exporter-7vxwm   minikube-m02
```

`DESIRED 2` was never specified — a DaemonSet has no `replicas` field. It derives
the count from the number of eligible nodes, which is why the 2-node cluster
matters. The manifest tolerates the control-plane taint, so the agent also lands
on the master — what a real telemetry or security collector must do.

📄 [`logs/07-daemonset-verification.txt`](./logs/07-daemonset-verification.txt) · 📸 [`07-daemonset-verification.png`](./screenshots/07-daemonset-verification.png)

---

## Task 8 — Rolling updates & instant rollback

Manifests: [`01-rolling-update/`](./01-rolling-update) — `maxSurge: 1`, `maxUnavailable: 0`.

Sampled once per second **during** the v1→v2 rollout:

```
TIME   TOTAL   READY   V1   V2
1s     4       3       3    1
5s     5       3       3    2
6s     4       3       2    2
9s     4       3       1    3
12s    3       3       0    3
```

This table *is* the zero-downtime proof: **READY never drops below 3**, the
declared replica count, at any instant.

`TOTAL` briefly reads 5, which looks like it violates `maxSurge: 1` (3+1=4). It
does not — `kubectl get pods` also counts pods in `Terminating` state. `maxSurge`
caps **non-terminated** pods at 4.

Rollback:

```
$ kubectl exec curl-client -- curl -s http://app-rolling-service
<h1>App Rolling</h1><p>VERSION: v2</p>

$ kubectl rollout undo deployment/app-rolling
$ kubectl exec curl-client -- curl -s http://app-rolling-service
<h1>App Rolling</h1><p>VERSION: v1</p>
```

Revision history went `1, 2` → `2, 3`: a rollback does not delete revision 2, it
replays revision 1's template as a **new** revision 3.

📄 [`logs/08-rolling-update-and-rollback.txt`](./logs/08-rolling-update-and-rollback.txt) · 📸 [`08-rolling-update-and-rollback.png`](./screenshots/08-rolling-update-and-rollback.png)

---

## Task 9 — Real-world troubleshooting drills

### Drill 1 — broken image stalls a rollout ([`troubleshooting/broken-image.yaml`](./troubleshooting/broken-image.yaml))

A healthy baseline ([`deployment-good.yaml`](./troubleshooting/deployment-good.yaml))
is applied first, so the broken manifest is an *update* — that is what lets the
old pods stay up.

```
$ kubectl rollout status deployment/yatri-backend --timeout=30s
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition

NAME                             READY   STATUS             RESTARTS   AGE
yatri-backend-856477d48-5dmq4    1/1     Running            0          31s
yatri-backend-856477d48-vqmlq    1/1     Running            0          31s
yatri-backend-856477d48-zdgfp    1/1     Running            0          31s
yatri-backend-86569d4ccf-hwskw   0/1     ImagePullBackOff   0          30s

NAME            READY   UP-TO-DATE   AVAILABLE   AGE
yatri-backend   3/3     1            3           31s
```

**Diagnosis.** `READY 3/3` and `AVAILABLE 3` but `UP-TO-DATE 1` is the signature of
a stalled rollout. The three v1 pods are still serving; only the single surged v2
pod is broken. `maxUnavailable: 0` is what guarantees this — Kubernetes refuses to
remove a healthy old pod until a new one is Ready, so a bad image tag becomes a
**stalled deploy instead of an outage**. Resolved with `kubectl rollout undo`.

### Drill 2 — immutable selector mismatch ([`troubleshooting/selector-mismatch.yaml`](./troubleshooting/selector-mismatch.yaml))

```
$ kubectl apply -f troubleshooting/selector-mismatch.yaml
The Deployment "selector-error-demo" is invalid: spec.template.metadata.labels:
Invalid value: {"app":"frontend"}: `selector` does not match template `labels`
```

Rejected by the API server at **admission time** — nothing was ever created. A
Deployment manages pods by *label selector*; if the selector (`app: backend`)
didn't match the pods the template produces (`app: frontend`), the ReplicaSet
could never adopt its own pods and would create them in an infinite loop. Fixed in
[`selector-fixed.yaml`](./troubleshooting/selector-fixed.yaml), which applies cleanly.

📄 [`logs/09-troubleshooting-drills.txt`](./logs/09-troubleshooting-drills.txt) · 📸 [`09-troubleshooting-drills.png`](./screenshots/09-troubleshooting-drills.png)

---

## Task 10 — Theoretical & architectural writeup

*Documentation task — no commands.*

### 10.1 The four ports

| Field | Lives on | Meaning |
|---|---|---|
| `containerPort` | Pod spec | The port the process listens on inside the container. **Purely informational** — it documents intent and does not open anything. |
| `targetPort` | Service | The pod-side port traffic is forwarded *to*. Must match what the app actually listens on. |
| `port` | Service | The port the Service itself exposes on its ClusterIP (the VIP). Callers inside the cluster use this. |
| `nodePort` | Service (`type: NodePort`) | A port in `30000–32767` opened on **every** node, forwarding into the Service. |

```
Client ──► nodePort 30080 (on any node IP)
             └─► port 8080 (Service ClusterIP)
                   └─► targetPort 80 (Pod)
                         └─► containerPort 80 (the nginx process)
```

Verified live in Session 11: a Service with `port: 8080` / `targetPort: 80`
answered on 8080 while the pods listened on 80.

### 10.2 Labels vs Selectors

- **Labels** are key/value metadata *attached to* objects: `app: nginx`, `slot: blue`.
- **Selectors** are *queries over* labels, used by controllers and Services to decide which objects they act on.

Labels are the data; selectors are the question. This indirection is what makes
the blue-green cutover in Task 11 possible: the pods never change, only the
question the Service asks about them.

### 10.3 The four deployment strategies

| Strategy | Mechanism | Downtime | Cost | Demonstrated |
|---|---|---|---|---|
| **RollingUpdate** | Replace pods gradually, bounded by `maxSurge`/`maxUnavailable` | None | ~1.1× | Task 8 |
| **Recreate** | Terminate all old pods, *then* start new ones | **Yes, deliberate** | 1× | Task 13 |
| **Blue-Green** | Two full environments; flip a Service selector | None | **2×** | Task 11 |
| **Canary** | Small % of new version beside stable, ratio by pod count | None | ~1.1× | Task 12 |

### 10.4 `maxSurge` vs `maxUnavailable`

For `replicas: 4`, `maxSurge: 1`, `maxUnavailable: 0`:
- Maximum pods during rollout = `4 + 1 = 5`
- Minimum available pods = `4 − 0 = 4` → 100% capacity maintained throughout

Both accept percentages, rounded **up** for `maxSurge` and **down** for
`maxUnavailable` — the rounding always favours availability. Setting both to 0 is
rejected: the rollout could never make progress.

*From the real run in Task 8* (`replicas: 3`, `maxSurge: 1`, `maxUnavailable: 0`):
non-terminated pods peaked at 4 and READY never fell below 3, exactly as the
arithmetic predicts.

### 10.5 Requests vs Limits, and GB vs GiB

- **Requests** — what the *scheduler* guarantees. Task 5's Pending pod requested
  512Gi and no node could satisfy it, so it never got scheduled at all.
- **Limits** — the ceiling the *kernel* enforces via cgroups. Exceeding a CPU limit
  causes **throttling**; exceeding a memory limit causes an **OOM kill**, because
  memory cannot be compressed the way CPU time can.

Units:

| Unit | Base | Bytes |
|---|---|---|
| `1 GB` | decimal, 10⁹ | 1,000,000,000 |
| `1 Gi` | binary, 2³⁰ | 1,073,741,824 |

A `Gi` is ~7.4% larger than a `G`. Kubernetes suffixes (`Mi`, `Gi`) are the binary
ones; writing `512M` instead of `512Mi` silently requests ~5% less memory.

---

## Task 11 — Blue-Green deployment & instant selector cutover

Manifests: [`02-blue-green/`](./02-blue-green). Both `service-blue.yaml` and
`service-green.yaml` define the **same** Service `myapp-service` — only the
`slot` selector differs. Applying the other file *is* the cutover.

```
$ kubectl describe svc myapp-service | grep -E 'Selector|Endpoints'
Selector:   app=myapp,slot=blue
Endpoints:  10.244.1.39:80,10.244.1.38:80,10.244.0.13:80
<h1>MyApp</h1><p>BLUE ENVIRONMENT</p>      (×6)

$ kubectl apply -f service-green.yaml
Selector:   app=myapp,slot=green
Endpoints:  10.244.1.41:80,10.244.0.14:80,10.244.1.40:80
<h1>MyApp</h1><p>GREEN ENVIRONMENT</p>     (×6)

$ kubectl apply -f service-blue.yaml       # instant rollback
Selector:   app=myapp,slot=blue
<h1>MyApp</h1><p>BLUE ENVIRONMENT</p>      (×4)
```

The endpoint set is replaced wholesale — 6/6 requests hit green, then 4/4 hit blue
again. There is no mixed-version window, because no pod is ever created or
destroyed during the switch. That is the trade: instant, atomic cutover in
exchange for running **2× the compute** the whole time.

> **A real issue found while running this.** The first attempt curled immediately
> after `kubectl apply` and got empty responses, then *stale GREEN* after flipping
> back to blue. The Service object updates atomically in the API, but the endpoints
> controller must rebuild the EndpointSlice and every node's kube-proxy must rewrite
> its iptables rules — roughly 1–2s. The fix was not a blind `sleep` but gating on
> observed state: wait until the Service's endpoint IPs equal the target slot's pod
> IPs, *then* send traffic. This is a genuine production consideration for
> selector-flip cutovers.

📄 [`logs/11-blue-green-cutover.txt`](./logs/11-blue-green-cutover.txt) · 📸 [`11-blue-green-cutover.png`](./screenshots/11-blue-green-cutover.png)

---

## Task 12 — Canary deployment & pod-ratio traffic splitting

Manifests: [`03-canary/`](./03-canary). The Service selects only
`app: myapp-canary`; both the stable and canary Deployments carry that label, so
**all** their pods become endpoints of one Service. The traffic split is therefore
simply the pod-count ratio.

**Measured over 40 in-cluster requests at each stage:**

| Stage | Stable pods | Canary pods | STABLE v1 | CANARY v2 | Canary share |
|---|---|---|---|---|---|
| Canary introduced | 9 | 1 | 36 | 4 | **10.0%** |
| Scaled up | 7 | 3 | 27 | 13 | **32.5%** |
| Aborted | 9 | 0 | 20 | 0 | **0%** |

```
$ kubectl exec curl-client -- sh -c 'for i in $(seq 1 40); do curl -s http://myapp-canary-service; done' | sort | uniq -c
  36 STABLE v1
   4 CANARY v2
```

The 9:1 pod ratio produced 36:4 — exactly 10%. Scaling to 3:7 produced 13:27
(32.5%, close to the nominal 30%; the residual is ordinary sampling variance over
40 requests, not a routing error).

Rollback needed **no image change and no rollout** — scaling the canary
Deployment to 0 removed its pods from the endpoint list and 20/20 requests
returned to stable. That is the main operational appeal of canary: aborting is a
scale operation, which is near-instant.

> The granularity limit is worth noting: with pod-count-based splitting, the
> smallest slice you can express with 9 stable pods is 1/10. Percentages finer
> than that need a service mesh doing weighted L7 routing.

📄 [`logs/12-canary-traffic-split.txt`](./logs/12-canary-traffic-split.txt) · 📸 [`12-canary-traffic-split.png`](./screenshots/12-canary-traffic-split.png)

---

## Task 13 — Recreate strategy & the downtime window

Manifests: [`04-recreate/`](./04-recreate) — `strategy.type: Recreate`.

A continuous request loop ran while v2 was applied (consecutive duplicates
collapsed):

```
VERSION: v1
   ... (x8 identical)
[OUTAGE] connection refused / 0 pods alive
   ... (x2 identical)
VERSION: v2 (UPGRADED)
   ... (x90 identical)
```

Two consecutive failures at ~0.5s intervals ≈ a **1 second total outage**. This is
not a bug — it is the defining behaviour of `Recreate`: every v1 pod is terminated
*before* any v2 pod is created, so there is a window with zero endpoints.

**The direct comparison with Task 8** is the point of running both:

| | Strategy | Failed requests | Peak pods |
|---|---|---|---|
| Task 8 | RollingUpdate (`maxUnavailable: 0`) | **0** | 4 |
| Task 13 | Recreate | **2** | 3 |

Recreate is still the right choice when two versions genuinely cannot coexist —
an incompatible database schema migration, or a singleton holding an exclusive
lock. You trade availability for a guarantee that v1 and v2 never run
simultaneously.

Rolling back re-runs the same strategy, so the rollback causes a second outage;
the verification curl is therefore gated on endpoints being restored.

📄 [`logs/13-recreate-downtime-outage.txt`](./logs/13-recreate-downtime-outage.txt) · 📸 [`13-recreate-downtime-outage.png`](./screenshots/13-recreate-downtime-outage.png)

---

## Manifest index

| Path | Contents |
|---|---|
| [`pod.yml`](./pod.yml) · [`hello.yml`](./hello.yml) · [`replicaset.yml`](./replicaset.yml) · [`deamonset.yml`](./deamonset.yml) | Tasks 2, 4, 6A, 7 |
| [`pod-lifecycle/`](./pod-lifecycle) | 12 lifecycle & probe manifests (Task 5) |
| [`k8s-core-objects/`](./k8s-core-objects) | StatefulSet + DaemonSet (Tasks 6B, 7) |
| [`01-rolling-update/`](./01-rolling-update) · [`deployment/`](./deployment) | Task 8 |
| [`02-blue-green/`](./02-blue-green) · [`03-canary/`](./03-canary) · [`04-recreate/`](./04-recreate) | Tasks 11, 12, 13 |
| [`troubleshooting/`](./troubleshooting) | Task 9 drills |
