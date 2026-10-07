# Session 13 — Kubernetes Storage, HPA & Probes

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · minikube v1.39.0 · Kubernetes v1.37.0 · **2-node cluster** · metrics-server v0.9.0

Manifests are taken from the course repository
(`devops-heros/session-13-storage-hpa-probes`) and run unmodified unless noted.
All output below is real; transcripts are in [`logs/`](./logs) and the rendered
screenshots in [`screenshots/`](./screenshots).

> **Screenshots** are rendered from the transcripts in `logs/` — the output is
> genuine, only the presentation is generated. The `.txt` files are the primary evidence.

---

## Task 1 — Kubernetes Volumes (documentation)

Full write-up: **[`01-kubernetes-volumes/README.md`](./01-kubernetes-volumes/README.md)**

It covers `emptyDir`, `hostPath`, PersistentVolume, PersistentVolumeClaim,
StorageClass and dynamic provisioning, each with a worked example verified on this
cluster — plus the two defects described below.

### Labs backing that document

| Lab | Manifests | Log |
|---|---|---|
| emptyDir & hostPath | [`01-volumes/`](./01-volumes) | [`01-volumes.txt`](./logs/01-volumes.txt) |
| Static PV + PVC | [`02-persistent-storage/`](./02-persistent-storage) | [`02-persistent-storage.txt`](./logs/02-persistent-storage.txt) |
| StorageClass / dynamic | [`03-storageclass/`](./03-storageclass) | [`03-storageclass.txt`](./logs/03-storageclass.txt) |

**hostPath proven to be real node storage** — the file is readable on the node itself:

```
$ kubectl exec hostpath-demo -- sh -c 'echo "hostPath survives the pod" > /data/persist.txt'
$ minikube ssh -n minikube-m02 -- 'cat /tmp/hostpath-data/persist.txt'
hostPath survives the pod
```

**PVC proven to outlive its pod:**

```
$ kubectl delete pod storage-demo   &&   kubectl apply -f pod.yaml
$ kubectl exec storage-demo -- cat /data/pvc.txt
persisted via PVC
```

### Defect 1 — the course PV and PVC never bind

```
$ kubectl get pv student-pv
NAME         CAPACITY   STATUS      CLAIM
student-pv   1Gi        Available            <-- never used

$ kubectl get pvc student-pvc
NAME          STATUS   VOLUME                                     STORAGECLASS
student-pvc   Bound    pvc-233df8df-baf7-48ca-a031-69755f785581   standard
```

`pvc.yaml` omits `storageClassName`, so the **default** StorageClass applies and a
new volume is provisioned dynamically; the hand-written PV is ignored. Setting
`storageClassName: ""` on the claim ([`pvc-static.yaml`](./02-persistent-storage/pvc-static.yaml))
bound it to `student-pv` immediately. The fix belongs on the claim — the PV was
always correct.

---

## Task 2 — HPA hands-on

Manifests: [`04-hpa/`](./04-hpa) — nginx with `cpu: 100m` requested, HPA targeting
**50% CPU**, `minReplicas: 1`, `maxReplicas: 5`, plus a
[`load-generator.yaml`](./04-hpa/load-generator.yaml) I added (4 pods × 20 parallel
request loops = 80 concurrent streams).

### Verify the HPA is reading metrics

```
$ kubectl get hpa hpa-demo
NAME       REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS
hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   1         5         1

$ kubectl top pods -l app=hpa-demo
NAME                        CPU(cores)   MEMORY(bytes)
hpa-demo-5d6676989b-kl5jf   0m           11Mi
```

> For the first ~60–90s after deploying, `TARGETS` reads `cpu: <unknown>/50%`.
> That is metrics-server not having completed a scrape cycle — not a broken HPA.
> `metrics-server` must be enabled (`minikube addons enable metrics-server`) or it
> never resolves.

### Scale-up under load

```
TIME    CPU/TARGET     REPLICAS  READYPODS
15s     0%/50%         1         1
60s     84%/50%        2         1
75s     84%/50%        2         2
120s    164%/50%       4         4
180s    63%/50%        4         4
240s    55%/50%        4         4
```

The autoscaler reacted within one 15s sync of load arriving, and reached its final
size in about two minutes.

It settled at **4**, not 5. The HPA formula is

```
desiredReplicas = ceil( currentReplicas × currentMetric / targetMetric )
```

which gives `ceil(4 × 55/50) = 5` — but the controller applies a **10% tolerance**
and ignores ratios between 0.9 and 1.1. At 55/50 = 1.10 it is exactly at the edge,
so no further scale-up is triggered. Measured CPU confirms the pods were genuinely
loaded and balanced:

```
$ kubectl top pods -l app=hpa-demo
hpa-demo-5d6676989b-258x2   56m   13Mi
hpa-demo-5d6676989b-jvbxn   54m   13Mi
hpa-demo-5d6676989b-kl5jf   54m   14Mi
hpa-demo-5d6676989b-ql2r8   56m   13Mi
```

### Scale-down — and the asymmetry that matters

```
TIME    CPU/TARGET     REPLICAS
15s     55%/50%        4
90s     35%/50%        4
150s    0%/50%         4          <-- CPU already at zero
...
360s    0%/50%         4
375s    0%/50%         3
435s    0%/50%         1          <-- back to minReplicas
```

CPU hit 0% at ~150s but **nothing moved until ~375s** — the default
`scaleDown.stabilizationWindowSeconds: 300`. Scale-up has no such window.

Kubernetes deliberately **scales out fast and scales in slowly**: adding capacity
you don't need is cheap, while removing capacity you're about to need again causes
an outage. This asymmetry is the single most useful thing to understand about HPA
behaviour in production.

📄 [`logs/04-hpa.txt`](./logs/04-hpa.txt) · 📸 [`04-hpa.png`](./screenshots/04-hpa.png)

---

## Task 2b — Probes

Manifests: [`05-probes/`](./05-probes)

| Probe | Question it answers | On failure |
|---|---|---|
| **startup** | has it finished booting? | keeps liveness suspended; kills the container if it never starts |
| **readiness** | should it receive traffic? | removed from Service endpoints — **no restart** |
| **liveness** | is it alive, or wedged? | container is **restarted** |

The distinction between readiness and liveness is best shown, not described. I broke
the readiness probe on a live pod by deleting nginx's index page:

```
$ kubectl get endpointslice ... 
ENDPOINTS      READY
[10.244.1.9]   true

$ kubectl exec readiness-demo -- rm /usr/share/nginx/html/index.html

$ kubectl get pod readiness-demo
NAME             READY   STATUS    RESTARTS   AGE
readiness-demo   0/1     Running   0          53s

$ kubectl get endpointslice ...
ENDPOINTS      READY
[10.244.1.9]   false

Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 403
```

`READY` went `1/1 → 0/1` and the endpoint flipped to `ready=false`, **but
`RESTARTS` stayed 0**. Readiness gates traffic; it never restarts anything.
Restoring the file brought the pod back into the endpoint set automatically.

📄 [`logs/05-probes.txt`](./logs/05-probes.txt) · 📸 [`05-probes.png`](./screenshots/05-probes.png)

---

## Task 3 — Mini Project

Manifests: [`mini-project/`](./mini-project) — namespace `production-webapp`
combining a PVC, an HPA and all three probes.

```
$ kubectl get all,pvc,hpa -n production-webapp
pod/web-app-d45775485-76qbt   1/1   Running
pod/web-app-d45775485-7j5jh   1/1   Running
service/web-service           ClusterIP   10.105.6.198   80/TCP
deployment.apps/web-app       2/2   2   2
hpa/web-app-hpa               Deployment/web-app   cpu: <unknown>/50%   2   5   2
pvc/web-data                  Bound   pvc-912dc038-...   500Mi   RWO   standard
```

All three probes active on every pod:

```
Liveness:   http-get http://:80/ delay=5s timeout=2s period=5s failureThreshold=3
Readiness:  http-get http://:80/ delay=5s timeout=2s period=5s failureThreshold=2
Startup:    http-get http://:80/ delay=0s timeout=1s period=2s failureThreshold=30
```

### Defect 2 — one PVC, two divergent copies

Writing through one pod and reading from the other **returned nothing**:

```
$ kubectl exec <pod on minikube-m02> -- sh -c 'echo "order-1234 written on minikube-m02" > /data/orders.txt'
order-1234 written on minikube-m02

$ kubectl exec <pod on minikube> -- ls -1 /data
                                            <-- EMPTY
```

Root cause:

```
provisioner : k8s.io/minikube-hostpath
hostPath    : /tmp/hostpath-provisioner/production-webapp/web-data
accessModes : ["ReadWriteOnce"]
nodeAffinity: []                            <-- nothing pins pods to the data
```

The provisioner creates the directory lazily on whichever node mounts it and sets
**no node affinity**, so a ReadWriteOnce PVC shared by a 2-replica Deployment
silently becomes one independent directory *per node*. Confirmed on the nodes:

```
minikube-m02:/tmp/hostpath-provisioner/production-webapp/web-data/   orders.txt
minikube:    /tmp/hostpath-provisioner/production-webapp/web-data/   (empty)
```

There is **no error and no event**. On a real cloud cluster the same manifest fails
*louder* — the second pod hangs in `ContainerCreating` because an EBS/PD volume
cannot attach to two nodes — which is safer than this silent split.

Persistence itself is fine; it is the cross-node *sharing* assumption that is wrong.
Holding the node constant, the data survives pod deletion exactly as intended:

```
$ kubectl delete pod <pod on minikube-m02>
$ kubectl exec <replacement on the same node> -- cat /data/orders.txt
order-1234 written on minikube-m02
```

### The fix — a StatefulSet with `volumeClaimTemplates`

[`mini-project/statefulset-fix.yaml`](./mini-project/statefulset-fix.yaml), verified:

```
$ kubectl get pvc -n production-webapp
web-data-web-app-sts-0   Bound   pvc-e2378be4-...   500Mi   RWO   standard
web-data-web-app-sts-1   Bound   pvc-c2fb0c32-...   500Mi   RWO   standard
```

Each ordinal owns a separate volume, so nothing is shared and nothing diverges.
If replicas must genuinely share one filesystem, ReadWriteOnce cannot do it on any
provider — that needs ReadWriteMany storage (NFS/EFS/CephFS).

📄 [`logs/06-mini-project.txt`](./logs/06-mini-project.txt) · 📸 [`06-mini-project.png`](./screenshots/06-mini-project.png)

---

## Manifest index

| Path | Contents |
|---|---|
| [`01-kubernetes-volumes/`](./01-kubernetes-volumes) | Task 1 documentation |
| [`01-volumes/`](./01-volumes) | `emptyDir`, `hostPath` pods |
| [`02-persistent-storage/`](./02-persistent-storage) | PV, PVC, pod + corrected static-binding pair |
| [`03-storageclass/`](./03-storageclass) | dynamic provisioning PVC |
| [`04-hpa/`](./04-hpa) | deployment, service, HPA, load generator |
| [`05-probes/`](./05-probes) | liveness, readiness, startup + endpoint-proof service |
| [`mini-project/`](./mini-project) | namespace, PVC, deployment, service, HPA + StatefulSet fix |

## Reproducing

```bash
minikube start --nodes=2 --driver=docker
minikube addons enable metrics-server
kubectl apply -f 04-hpa/deployment.yaml -f 04-hpa/service.yaml -f 04-hpa/hpa.yaml
kubectl apply -f 04-hpa/load-generator.yaml
kubectl get hpa hpa-demo -w          # watch it scale 1 -> 2 -> 4
kubectl delete -f 04-hpa/load-generator.yaml
```
