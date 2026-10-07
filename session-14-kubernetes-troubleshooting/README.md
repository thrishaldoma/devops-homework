# Session 14 — Kubernetes Troubleshooting

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · minikube v1.39.0 · Kubernetes v1.37.0 · 2-node cluster

Manifests come from the course repository
(`devops-heros/session-14-kubernetes-troubleshooting`). Every issue below was
genuinely reproduced, diagnosed and fixed on a live cluster. Transcripts in
[`logs/`](./logs), rendered screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/` — the output is
> genuine, only the presentation is generated.

---

## Task 1 — The eight troubleshooting commands

| # | Command | Answers |
|---|---|---|
| 1 | `kubectl get` | **What** exists, and in what state? |
| 2 | `kubectl get -o wide` | **Where** is it running, on which IP/node? |
| 3 | `kubectl describe` | **Why** is it in that state? (Events live here) |
| 4 | `kubectl logs` | What did the **application** say? |
| 5 | `kubectl exec` | Prove it from **inside** the container |
| 6 | `kubectl events` | A cluster-wide **timeline** |
| 7 | `kubectl explain` | The API **schema**, offline |
| 8 | `kubectl top` | What is it **actually consuming**? |

```
$ kubectl get pods -o wide
NAME            READY   STATUS    RESTARTS   AGE   IP            NODE
describe-demo   1/1     Running   0          46s   10.244.1.23   minikube-m02
...

$ kubectl top pods
NAME       CPU(cores)   MEMORY(bytes)
get-demo   3m           11Mi
```

**The triage order that matters:**

```
get  (what / where)  ->  describe (why: scheduling + kubelet events)
                     ->  logs     (the application's own words)
                     ->  exec     (prove it from inside)
```

`describe` answers **infrastructure** failures; `logs` answers **application**
failures. Knowing which you have cuts the search space in half.

📄 [`logs/01-kubectl-commands.txt`](./logs/01-kubectl-commands.txt) · 📸 [`01-kubectl-commands.png`](./screenshots/01-kubectl-commands.png)

---

## Task 2 — Troubleshooting common issues

Every issue follows **identify → investigate → root cause → fix → verify**.

### CrashLoopBackOff

```
$ kubectl get pod crash-demo
NAME         READY   STATUS   RESTARTS      AGE
crash-demo   0/1     Error    3 (30s ago)   45s

$ kubectl describe pod crash-demo | grep -A 6 'Last State'
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
    Restart Count:  3

$ kubectl logs crash-demo
Application starting...
Something went wrong!
```

**Root cause:** the process exits 1. `restartPolicy` defaults to `Always`, so the
kubelet restarts it, it exits again, and the backoff grows (10s, 20s, 40s…).
`CrashLoopBackOff` names the **wait between restarts**, not a crash in progress —
which is why you often catch the pod in `Error` instead.

**Fix:** make the process stay alive. **Verified:** `1/1 Running`, logs show
`Application is healthy`.

📄 [`logs/02-crashloopbackoff.txt`](./logs/02-crashloopbackoff.txt)

### ImagePullBackOff / ErrImagePull

```
$ kubectl get pod image-demo        # at 14s
image-demo   0/1   ErrImagePull       0   14s
$ kubectl get pod image-demo        # at 36s
image-demo   0/1   ImagePullBackOff   0   36s

$ kubectl logs image-demo
Error from server (BadRequest): container "app" in pod "image-demo" is waiting
to start: image can't be pulled
```

`ErrImagePull` is the **first** failure; `ImagePullBackOff` is the kubelet backing
off. Note that **`kubectl logs` is useless here** — no container ever started, so
only Events carry the diagnosis. That single observation is the fastest way to tell
an infrastructure failure from an application one.

📄 [`logs/03-imagepullbackoff.txt`](./logs/03-imagepullbackoff.txt)

### Pending

```
Warning  FailedScheduling  0/2 nodes are available: 2 node(s) didn't match
                           Pod's node affinity/selector.

$ kubectl get pod pending-demo -o jsonpath='{.spec.nodeSelector}'
{"kubernetes.io/hostname":"node-that-does-not-exist"}
```

**Root cause:** `Pending` means *not yet scheduled* — the pod has no node and no IP,
so the **scheduler** is the suspect, never the kubelet. Here a `nodeSelector`
demands a node that does not exist.

📄 [`logs/04-pending-pods.txt`](./logs/04-pending-pods.txt)

### Service connectivity & DNS

```
$ kubectl exec dns-test -- nslookup broken-service | grep -A 2 'Name:'
Name:   broken-service.default.svc.cluster.local
Address: 10.100.104.254              <-- DNS is FINE

$ kubectl describe svc broken-service | grep -E 'Selector:|Endpoints:'
Selector:   app=does-not-exist
Endpoints:                           <-- the actual problem
```

**Root cause:** the selector matches no pod (`app=does-not-exist` vs `app=web`), so
the EndpointSlice is empty and there is nowhere to route.

A Service with **no endpoints still resolves in DNS and still has a ClusterIP**.
That is precisely why "nslookup works, so DNS is fine" sends people down the wrong
path — the failure is at the routing layer, not the naming layer.

> **Two defects in the course material for this drill**, both corrected here:
> - `dns-test-pod.yaml` pins `registry.k8s.io/e2e-test-images/dnsutils:1.3`, which
>   has no arm64 manifest (`docker manifest inspect` → `no such manifest`) and lands
>   in ImagePullBackOff. Corrected in [`dns-test-pod-fixed.yaml`](./09-service-dns-troubleshooting/dns-test-pod-fixed.yaml).
> - `service.yaml`, presented as the *fix*, selects `app: web-ahsgdf` — a typo — so
>   it has no endpoints either. Corrected in [`service-fixed.yaml`](./09-service-dns-troubleshooting/service-fixed.yaml).

📄 [`logs/05-service-dns.txt`](./logs/05-service-dns.txt)

---

## Task 2b — The triage gauntlet (5 simultaneous failures)

[`scenarios/triage_all.sh`](./scenarios/triage_all.sh) deploys five broken
workloads at once:

```
NAME                     READY   STATUS             RESTARTS
fail-1-crashloop-pod     0/1     Error              3
fail-2-imagepull-pod     0/1     ImagePullBackOff   0
fail-3-pending-pod       0/1     Pending            0
fail-4-dns-failure-pod   1/1     Running            0      <-- "healthy"!
fail-5-oomkilled-pod     0/1     OOMKilled          3
```

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | `Error`, restarts climbing | app exits 1 — `DATABASE_URL` unset (**configuration**, not infrastructure) | supply the env var |
| 2 | `ImagePullBackOff` | image has no registry prefix → resolves to `docker.io/library/…` which doesn't exist | real image reference |
| 3 | `Pending` | requests **500 CPU / 1000Gi** against nodes with 15 allocatable CPUs | request what it needs |
| 4 | **`Running`** | wrong hostname → `NXDOMAIN`; nothing surfaces it | correct FQDN + readiness probe |
| 5 | `OOMKilled`, exit 137 | allocates ~1GB against a 20Mi limit | raise limit / fix the leak |

**Scenario 4 is the instructive one.** `STATUS: Running` tells you nothing about
whether the application works — only the logs revealed the failed call. A
**readiness probe** would have surfaced it, which is the real lesson: without
probes, Kubernetes cannot distinguish "process alive" from "application working".

**Scenario 5**, exit code **137** = 128 + SIGKILL(9). Memory is *incompressible*:
exceeding a CPU limit only throttles, but exceeding a memory limit kills the
container outright.

**Pods are immutable.** `kubectl set env pod/...` was rejected —
only `image`, `tolerations`, `activeDeadlineSeconds` and
`terminationGracePeriodSeconds` can change on a running Pod. Every fix is therefore
delete-and-recreate; this is a large part of why you deploy Deployments, not Pods.

All five verified fixed:

```
NAME                     READY   STATUS    RESTARTS
fail-1-crashloop-pod     1/1     Running   0
fail-2-imagepull-pod     1/1     Running   0
fail-3-pending-pod       1/1     Running   0
fail-4-dns-failure-pod   1/1     Running   0
fail-5-oomkilled-pod     1/1     Running   0
```

### Bonus issue found while verifying: empty logs from a healthy pod

Two pods were `Running` with 0 restarts yet returned **nothing** from
`kubectl logs` — which looks like a broken logging pipeline.

**Root cause:** Python buffers stdout when it is not a TTY. The process printed,
then slept for an hour, so the buffer was never flushed and the kubelet had nothing
to collect. The application was fine; the **observability** was broken — which is
worse, because it blinds you during an incident.

**Fix:** `PYTHONUNBUFFERED=1` (or `print(..., flush=True)`, or `python3 -u`).
After the fix the logs appear immediately:

```
$ kubectl logs fail-1-crashloop-pod
Application started successfully! DATABASE_URL=postgres://postgres.default.svc.cluster.local:5432/yatri
```

📄 [`logs/06-triage-gauntlet.txt`](./logs/06-triage-gauntlet.txt) · 📸 [`06-triage-gauntlet.png`](./screenshots/06-triage-gauntlet.png)

---

## Task 3 — Mini Project

[`mini-project/`](./mini-project) — deploy → observe → break → investigate → fix → verify.

**Baseline first** (you cannot recognise "broken" without knowing "good"):

```
$ kubectl describe svc troubleshooting-service | grep -E 'Selector:|TargetPort:|Endpoints:'
Selector:     app=troubleshooting-app
TargetPort:   80/TCP
Endpoints:    10.244.1.44:80,10.244.0.16:80
```

**Break 1 — bad image tag.** The broken pod went `ErrImagePull`, while the
Deployment's pods stayed `1/1 Running`. Scoping the blast radius first prevents
chasing a cluster-wide outage that isn't one.

**Break 2 — `targetPort` mismatch.** This one fails *differently*, and is easy to
misdiagnose:

```
$ kubectl describe svc troubleshooting-service | grep -E 'Selector:|TargetPort:|Endpoints:'
Selector:     app=troubleshooting-app          <-- correct
TargetPort:   8080/TCP                         <-- wrong
Endpoints:    10.244.1.44:8080,10.244.0.16:8080,10.244.1.46:8080

$ curl http://troubleshooting-service
curl: (7) Failed to connect ... Could not connect to server
```

Endpoints **exist**, so the usual selector check passes — but nginx listens on 80,
not 8080, so every connection is refused.

### The diagnostic rule worth memorising

```
no endpoints at all          ->  selector / label mismatch
endpoints present, refused   ->  targetPort / containerPort mismatch
name does not resolve        ->  genuine DNS / CoreDNS problem
```

Both breaks repaired and verified (`<title>Welcome to nginx!</title>`).

📄 [`logs/07-mini-project.txt`](./logs/07-mini-project.txt) · 📸 [`07-mini-project.png`](./screenshots/07-mini-project.png)

---

## Manifest index

| Path | Contents |
|---|---|
| [`01-kubectl-get/`](./01-kubectl-get) … [`05-events/`](./05-events) | command-practice pods |
| [`06-crashloopbackoff/`](./06-crashloopbackoff) · [`07-imagepullbackoff/`](./07-imagepullbackoff) · [`08-pending-pods/`](./08-pending-pods) | broken/fixed pairs |
| [`09-service-dns-troubleshooting/`](./09-service-dns-troubleshooting) | service + DNS drill, with corrected manifests |
| [`scenarios/`](./scenarios) | 5-scenario triage gauntlet + `fixed.yaml` for each |
| [`mini-project/`](./mini-project) | end-to-end triage walk |
