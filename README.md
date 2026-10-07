# DevOps Homework — Linux to Kubernetes

**Name:** THRISHAL DOMA
**Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64, Apple Silicon) + Docker Desktop 4.89.0 / Engine 29.7.2
**Completed:** 4 September 2026 (Linux–Docker) · 18 September 2026 (Kubernetes)

Complete solutions for all homework tasks across Linux, shell scripting,
networking, Git, Docker and Kubernetes. Each folder has its own README containing
the commands, their real captured output, and screenshots.

Sessions 09–12 (Kubernetes) were run against a live **2-node minikube cluster**
(Kubernetes v1.37.0, containerd 2.3.4). See
[Kubernetes sessions](#kubernetes-sessions-0912) below.

Linux-only tasks (`adduser`, `useradd`, `journalctl`) were executed inside an
Ubuntu 22.04 container running systemd as PID 1, because macOS provides
neither systemd nor those utilities. The image definition is in
``01-linux/lab-environment/Dockerfile``.

## Index

> **What is in this repository.** Sessions **13–20** are published here. Sessions
> **01–12** were completed earlier and are kept locally rather than published, so
> their folders are shown unlinked below. Every link in the table resolves.

| # | Topic | Folder | Tasks |
|---|---|---|---|
| 01 | Linux Fundamentals | `01-linux/` *(local only)* | links · adduser vs useradd · journalctl · cheat sheet |
| 02 | Shell Scripting | `02-shell-scripting/` *(local only)* | system information script |
| 03 | Networking | `03-networking/` *(local only)* | IP/subnetting · command lab · macOS equivalents |
| 04 | Git / GitHub | `04-git-github/` *(local only)* | `commit -a -m` · cherry-pick |
| 05 | Docker Fundamentals | `05-docker-apps/` *(local only)* | six Hello World web apps |
| 06 | Multi-Stage Builds | `06-docker-multistage/` *(local only)* | multi-stage image on port 8080 |
| 07 | Networking & Volumes | `07-docker-network-volume/` *(local only)* | 3 networks · host network · bind mount · overlay |
| 09 | Kubernetes Fundamentals | `session9-k8s/` *(local only)* | minikube setup · cluster lifecycle · architecture writeup |
| 10 | Core Objects & Strategies | `session10-k8s-core-objects/` *(local only)* | pods · probes · ReplicaSet/StatefulSet/DaemonSet · rolling · blue-green · canary · recreate |
| 11 | Services, DNS & Identity | `session-11-kubernetes-services/` *(local only)* | ClusterIP · NodePort · LoadBalancer · ExternalName · headless · CoreDNS/ndots |
| 12 | Ingress, ConfigMaps & Secrets | `session-12-ingress-configmaps-secrets/` *(local only)* | ConfigMaps · Secrets · path/host routing · TLS termination |
| 13 | Storage, HPA & Probes | [`session-13-storage-hpa-probes/`](./session-13-storage-hpa-probes) | volumes · PV/PVC · StorageClass · HPA autoscaling · probes |
| 14 | Troubleshooting | [`session-14-kubernetes-troubleshooting/`](./session-14-kubernetes-troubleshooting) | 8 triage commands · 5-scenario gauntlet · service/DNS debugging |
| 15 | Helm | [`session-15-helm/`](./session-15-helm) | chart authoring · install/upgrade/rollback · one chart, two environments |
| 16 | CI/CD & GitHub Actions | [`session-16-github-actions/`](./session-16-github-actions) | CI pipeline · CD pipeline · Docker build · artifacts |

## Kubernetes sessions (09–12)

| | |
|---|---|
| Cluster | `minikube start --nodes=2 --driver=docker` — **2 nodes**, Kubernetes v1.37.0, containerd 2.3.4 |
| Manifests | 60 YAML files, every one validated with `kubectl apply --dry-run=server` |
| Evidence | 41 transcripts in each session's `logs/`, 41 rendered screenshots in `screenshots/` |
| Addons | `ingress` (ingress-nginx v1.15.1), `metallb` (stands in for a cloud LB controller) |

Two nodes rather than one because several exercises are meaningless on a single
node — a DaemonSet scheduling one pod *per node*, and a NodePort answering on a
node that hosts none of the app's pods.

### Screenshots

The assignment asks for terminal screenshots. There is no interactive terminal
session to photograph here, so each PNG in `screenshots/` is **rendered from the
matching `.txt` transcript** by [`_tools/render-terminal.py`](./_tools/render-terminal.py).
The output is genuine captured output; only the presentation is generated, and
nothing is truncated. **The `.txt` logs in each `logs/` folder are the primary
evidence** and every README links them alongside the image.

### Environment deviations

Four constraints of this machine changed *how* some commands were run, never
whether the underlying behaviour was demonstrated. Each is called out again in the
session README where it applies:

1. **No passwordless `sudo`.** `minikube tunnel` (needs root for host routes and
   privileged ports) and `/etc/hosts` edits were not used. Substituted:
   `minikube service --url`, `kubectl port-forward`, and `curl -H 'Host: ...'` /
   `--resolve`. The Ingress controller routes on the Host header, so sending it
   explicitly exercises exactly the same path an `/etc/hosts` entry would.
2. **`$(minikube ip)` is unreachable from macOS.** With the Docker driver the node
   lives on a bridge inside Docker Desktop's VM; the host has no route to
   `192.168.49.0/24`. This is analysed with evidence in Session 11, Task 12 — it is
   one of the assignment's own topics, so it is documented rather than worked
   around silently.
3. **Traffic-split tests run inside the cluster.** Sessions 10's blue-green, canary
   and recreate tests curl from a pod rather than the host. This is not only a
   workaround but the *correct* method: `kubectl port-forward` pins a single pod,
   which would have reported 100% of one version and destroyed the canary
   measurement. In-cluster requests traverse the Service VIP and are load-balanced
   by kube-proxy, so the measured 9:1 ratio is real.
4. **MetalLB substitutes for a cloud load-balancer controller**, so
   `type: LoadBalancer` reaches a real `EXTERNAL-IP` instead of `<pending>`. Its
   layer-2 address is reachable from the node, not from macOS — same cause as (2).

### Reproducing

```bash
minikube start --nodes=2 --driver=docker --cpus=2 --memory=3000
minikube addons enable ingress
# then follow the "Reproducing" section in each session README
```

### Cluster state as delivered

Every workload created by these sessions has been deleted — the `default`
namespace is empty apart from the built-in `kubernetes` Service. The cluster
itself is left **running** so the work can be re-verified; the `ingress` and
`metallb` addons remain enabled.

```bash
minikube stop      # power the nodes off, keep the cluster and its images
minikube delete    # remove the cluster entirely
```

## Applications and ports

| App | Stack | Host port | URL |
|---|---|---|---|
| nodejs-app | Node 20 + Express | 3000 | http://localhost:3000 |
| python-app | Python 3.11 + Flask | 5001 | http://localhost:5001 |
| java-app | Temurin 21 | 8081 | http://localhost:8081 |
| Apache-app | httpd 2.4 | 8082 | http://localhost:8082 |
| React-app | Vite + Nginx | 3001 | http://localhost:3001 |
| nginx-app | nginx:alpine | 8083 | http://localhost:8083 |
| multistage | Node 24 multi-stage | 8080 | http://localhost:8080 |

Port 5001 is used instead of 5000 because macOS AirPlay Receiver occupies
port 5000 on Monterey and later. The Python container still listens on 5000
internally — only the host side of the mapping moves.

## Reproducing this work

```bash
# Six apps
cd 05-docker-apps && docker compose up -d --build

# Multi-stage on port 8080
cd ../06-docker-multistage
docker build -t multistage-hello:v1 .
docker run -d --name multistage-app -p 8080:3000 multistage-hello:v1
curl localhost:8080
```

Note that `docker compose up` and the individually-named containers cannot run at
the same time — they publish the same host ports and would collide. The compose
file is shipped as a convenience for rebuilding all six apps in one command.

## Raw evidence (Sessions 01-12, local only)

> The files referenced in this section live in the local working copy and are not
> published in this repository. They are shown as plain paths rather than links.


``logs/`` contains the complete unedited transcript of every command run,
one file per phase, produced by ``_tools/run.sh`` at the moment
each command ran. Nothing in any README was written from memory.

``logs/ISSUES.md`` records everything that did not work first
time and how it was handled — including a missing Docker installation, an occupied
port, and a real intermittent DNS fault on the host network.

``_tools/verify.sh`` is the automated acceptance checker; its
output is saved to ``logs/99-acceptance.log``.

## Acceptance results

Two automated checkers were run against this deliverable, both after the Docker
teardown so the results reflect the folder as delivered:

| Checker | Result |
|---|---|
| ``_tools/verify.sh`` — the playbook's Section 10.2 checker | **57 passed, 0 failed — ACCEPTANCE: PASS** |
| ``_tools/appendix-c.sh`` — every Appendix C criterion | **110 passed, 0 failed — APPENDIX C: PASS** |

Their output is saved to ``logs/99-acceptance.log`` and
``logs/99-appendix-c.log``. Both checkers assert against
the log files and the filesystem rather than against recollection — every claim in
every README was cross-checked against the raw transcript that produced it.

## Docker cleanup

Every container, image, network and volume created by this run was removed by
exact name — see ``logs/98-teardown.log``. No blanket
`docker system prune`, `docker rmi $(docker images -q)` or similar was ever used.

The state before the run was captured in
``logs/00-docker-baseline.log`` and the state after
teardown matches it exactly: **0 containers, 0 volumes, and only the three default
networks** (`bridge`, `host`, `none`).

The base images that were pulled are **left in place**, as the playbook permits,
since deleting them is the user's decision:

| Image | Size |
|---|---|
| `mysql:8.0` | 1.09 GB |
| `eclipse-temurin:21-jdk-alpine` | 556 MB |
| `eclipse-temurin:21-jre-alpine` | 287 MB |
| `node:24-alpine` | 231 MB |
| `python:3.11-slim` | 226 MB |
| `httpd:2.4` | 207 MB |
| `node:20-alpine` | 194 MB |
| `ubuntu:22.04` | 109 MB |
| `nginx:alpine` | 102 MB |
| `alpine:latest` | 13.6 MB |

That is **2.825 GB** of images plus **1.03 GB** of build cache. To reclaim it:

```bash
docker builder prune          # the 1.03 GB of build cache
docker rmi mysql:8.0 eclipse-temurin:21-jdk-alpine eclipse-temurin:21-jre-alpine \
           node:24-alpine python:3.11-slim httpd:2.4 node:20-alpine \
           ubuntu:22.04 nginx:alpine alpine:latest
```

## One change made outside this folder

Everything this run produced lives in `~/devops-homework` and `/tmp`, with a single
declared exception that is worth knowing about because it affects your machine
rather than this homework.

Docker Desktop could not start at all on this macOS build — Apple's
Virtualization.framework was failing with `VZErrorInternal`, leaving
`docker desktop status` stuck at `starting` indefinitely. With explicit
authorisation, two keys were changed in
`~/Library/Group Containers/group.com.docker/settings-store.json`:

```json
"UseVirtualizationFramework": false,
"UseVirtualizationFrameworkRosetta": false
```

This switches Docker Desktop from Apple's hypervisor to **Docker VMM** (libkrun).
The daemon then started immediately and every container phase ran normally.

**To revert:** set `UseVirtualizationFramework` back to `true` — or delete both
keys, which restores the defaults — and relaunch Docker Desktop. The only
practical cost of leaving it as-is is that `--platform linux/amd64` emulation via
Rosetta is unavailable; every image used here is multi-architecture and runs
natively on `aarch64`.

The full diagnosis, with the log evidence that identified it, is Issue 4 in
``logs/ISSUES.md``. The Appendix C checker reports this
deviation explicitly rather than omitting it.

## A note on Git

This folder is deliberately **not** a Git repository. It contains no `.git`
directory, no `.gitignore` and no repository scaffolding of any kind, so that it
can be added to a repository of your own choosing without becoming a broken
nested repository or an accidental submodule.

The Git tasks in Part 04 do require a real repository. That work was done in a
disposable sandbox under `/tmp/git-sandbox`, captured as plain text into
``04-git-github/transcript.txt``, and the sandbox
was then deleted. Repository-local `git config` was used throughout, so the
machine's global Git identity was never modified.

## Reference

Course material: https://github.com/Nency-Ravaliya/devops-heros
(downloaded as a tarball with `curl`, never cloned, so no `.git` was introduced.)
