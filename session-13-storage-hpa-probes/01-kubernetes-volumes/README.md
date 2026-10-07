# Kubernetes Volumes — Storage Concepts

**Session 13, Task 1.** Everything below was verified on a live 2-node minikube
cluster; the captured transcripts are in [`../logs/`](../logs).

---

## The problem volumes solve

A container's filesystem is **ephemeral**. When a container restarts, anything it
wrote is gone — the kubelet starts a fresh container from the image. Volumes give
a pod storage whose lifetime is decoupled from the container's.

The question each volume type answers is *how long does the data live, and who can see it?*

| Type | Lifetime | Scope | Use for |
|---|---|---|---|
| `emptyDir` | the **pod** | one pod | scratch space, caches, sharing files between containers in a pod |
| `hostPath` | the **node** | one node | node agents that must read the host (logs, `/proc`, docker socket) |
| `PersistentVolume` + `PVC` | **independent of pods** | cluster-managed | databases, uploads, anything that must survive rescheduling |

---

## 1. `emptyDir` — scratch space that dies with the pod

Created empty when the pod is assigned to a node, deleted permanently when the pod
is removed. Survives a *container* restart; does **not** survive pod deletion.

```yaml
volumes:
  - name: app-storage
    emptyDir: {}
```

Verified ([`01-volumes.txt`](../logs/01-volumes.txt)):

```
$ kubectl describe pod emptydir-demo | grep -A 3 'Volumes:'
Volumes:
  app-storage:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
```

`emptyDir: {}` is backed by the node's disk. Setting `medium: Memory` makes it a
tmpfs instead — fast, but it counts against the container's memory limit.

**Main use:** a sidecar sharing files with the app container. Session 10's
multi-container pod used exactly this to let a logging sidecar tail the app's log.

---

## 2. `hostPath` — a directory on the node

Mounts a path from the **node's** filesystem into the pod.

```yaml
volumes:
  - name: host-storage
    hostPath:
      path: /tmp/hostpath-data
      type: DirectoryOrCreate
```

Verified — the file is genuinely on the node, outside any container:

```
$ kubectl exec hostpath-demo -- sh -c 'echo "hostPath survives the pod" > /data/persist.txt'
$ minikube ssh -n minikube-m02 -- 'cat /tmp/hostpath-data/persist.txt'
hostPath survives the pod
```

Deleting and recreating the pod kept the data, because it landed on the same node.

**That last clause is the catch.** `hostPath` data is tied to one node. If the pod
is rescheduled elsewhere it silently sees an empty directory. It is also a
**security risk** — mounting `/` or the container runtime socket gives the pod
effective control of the node, which is why most clusters restrict it by policy.

**Legitimate use:** DaemonSet node agents (Session 10 ran `node-exporter` with a
`hostPath` of `/` to read host metrics). For ordinary applications, use a PVC.

---

## 3. PersistentVolume (PV) — the storage itself

A **cluster-scoped** object representing a real piece of storage. Created either by
an administrator (static) or automatically by a provisioner (dynamic).

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: student-pv
spec:
  capacity: { storage: 1Gi }
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  hostPath: { path: /tmp/student-data }
```

**Access modes**

| Mode | Short | Meaning |
|---|---|---|
| `ReadWriteOnce` | RWO | mountable read-write by **one node** |
| `ReadOnlyMany` | ROX | read-only by many nodes |
| `ReadWriteMany` | RWX | read-write by **many nodes** (needs NFS/EFS/CephFS) |
| `ReadWriteOncePod` | RWOP | read-write by exactly **one pod** |

RWO is per-**node**, not per-pod — two pods on the *same* node can share an RWO
volume, which is a common source of confusion.

**Reclaim policy** — what happens to the data when the claim is deleted:
- `Retain` — volume and data kept, must be reclaimed manually. Use for anything important.
- `Delete` — volume and data destroyed with the claim. The default for most dynamic classes.

---

## 4. PersistentVolumeClaim (PVC) — a request for storage

A **namespaced** request for size + access mode. Pods reference the *claim*, never
the volume, which is what decouples the app from the storage implementation.

```yaml
volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: student-pvc
```

Verified that data outlives the pod ([`02-persistent-storage.txt`](../logs/02-persistent-storage.txt)):

```
$ kubectl exec storage-demo -- sh -c 'echo "persisted via PVC" > /data/pvc.txt'
$ kubectl delete pod storage-demo
$ kubectl apply -f pod.yaml          # new pod
$ kubectl exec storage-demo -- cat /data/pvc.txt
persisted via PVC
```

---

## 5. StorageClass & dynamic provisioning

A StorageClass is a **template** for creating volumes on demand, so nobody has to
pre-create PVs by hand.

```
$ kubectl get storageclass
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
```

A PVC naming a class gets a volume created for it automatically:

```
$ kubectl apply -f 03-storageclass/pvc.yaml
$ kubectl get pvc dynamic-pvc
NAME          STATUS   VOLUME                                     CAPACITY   STORAGECLASS
dynamic-pvc   Bound    pvc-68c37315-6d5a-42c2-9140-ed29f60656b4   500Mi      standard
```

No PV was written by hand — the provisioner created `pvc-68c3...` in response to
the claim. On AWS the same PVC would produce an EBS volume; on GCP a PD. That
portability is the point: the manifest does not change, only the StorageClass does.

`volumeBindingMode` matters on multi-node clusters:
- `Immediate` — bind as soon as the PVC is created, possibly before the pod is scheduled.
- `WaitForFirstConsumer` — wait until a pod is scheduled, then provision on *that* node. This is what avoids the topology mismatch described below.

---

## Two real defects found while running this lab

### A PVC that omits `storageClassName` ignores your hand-made PV

The course's `student-pv` and `student-pvc` do not bind to each other:

```
$ kubectl get pv student-pv
NAME         CAPACITY   STATUS      CLAIM
student-pv   1Gi        Available            <-- never used

$ kubectl get pvc student-pvc
NAME          STATUS   VOLUME                                     STORAGECLASS
student-pvc   Bound    pvc-233df8df-baf7-48ca-a031-69755f785581   standard
```

The claim omits `storageClassName`, so Kubernetes applied the **default** class and
dynamically provisioned a brand-new volume. The hand-made PV was never considered.

```
omitted storageClassName  ->  default StorageClass  ->  DYNAMIC provisioning
storageClassName: ""      ->  no class              ->  STATIC binding to an existing PV
```

Setting `storageClassName: ""` on the claim bound it to `student-pv` immediately.
The fix belongs on the **claim**; the PV was fine all along.

### RWO + multiple replicas = silent data divergence

The mini-project runs a 2-replica Deployment against one ReadWriteOnce PVC. On this
cluster that produced **two independent directories, one per node**, with no error:

```
pod on minikube-m02:  /data/orders.txt   ("order-1234 written on minikube-m02")
pod on minikube:      /data              (empty)

$ kubectl get pv <name> -o jsonpath='{.spec.nodeAffinity}'
[]                                        <-- no affinity, nothing pins the pods
```

minikube's hostpath provisioner creates the directory lazily on whichever node
mounts it and sets no `nodeAffinity`. On a real cloud cluster this fails *louder* —
the second pod hangs in `ContainerCreating` because an EBS/PD volume cannot attach
to two nodes — which is safer than this silent split.

**Correct patterns:**
1. **ReadWriteMany** storage (NFS, EFS, CephFS) if replicas genuinely share a filesystem.
2. **StatefulSet with `volumeClaimTemplates`** — one volume per replica. Verified working in [`../mini-project/statefulset-fix.yaml`](../mini-project/statefulset-fix.yaml):
   ```
   web-data-web-app-sts-0   Bound   pvc-e2378be4-...   500Mi   RWO
   web-data-web-app-sts-1   Bound   pvc-c2fb0c32-...   500Mi   RWO
   ```
3. **`replicas: 1`** if the data is genuinely single-writer.

---

## Decision guide

```
Does the data need to outlive the POD?
│
├── NO ──► emptyDir
│
└── YES ─► Does it need to outlive the NODE?
            │
            ├── NO, and it IS node data (logs, metrics, host files)
            │      └──► hostPath  (DaemonSets only; restricted by policy)
            │
            └── YES ──► PVC
                         ├── one writer / per-replica data ──► RWO
                         │     └── many replicas? use a StatefulSet
                         │         with volumeClaimTemplates
                         └── genuinely shared across nodes ──► RWX (NFS/EFS)
```
