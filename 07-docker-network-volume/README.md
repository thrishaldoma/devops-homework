# Part 07 — Docker Networking & Volumes

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Host:** macOS 26.6.2 (arm64) + Docker Engine 29.7.2

---

## Task 1 — Three containers, three networks, deliberate isolation

### The topology

```
   ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
   │   frontend    │      │    backend    │      │   database    │
   │    alpine     │      │    alpine     │      │   mysql:8.0   │
   └───────┬───────┘      └───┬───────┬───┘      └───┬───────┬───┘
           │                  │       │              │       │
   frontend-net ──────────────┘       │              │       │
   backend-net  ──────────────────────────────────────┘       │
   db-net       ──────────────────────────────────────────────┘

   frontend  ──▶ backend    REACHABLE   both on frontend-net
   backend   ──▶ database   REACHABLE   both on backend-net
   frontend  ──▶ database   BLOCKED     no network in common
```

`backend` is the only path between tiers, because it is the only container on two
networks.

### Creating the networks

```bash
$ docker network create frontend-net
$ docker network create backend-net
$ docker network create db-net

$ docker network ls
NETWORK ID     NAME           DRIVER    SCOPE
f2ed42fbb91c   backend-net    bridge    local
c2be6c3374ec   bridge         bridge    local
9f577d9523f9   db-net         bridge    local
938608324f0c   frontend-net   bridge    local
8da6b07fd132   host           host      local
826e9c36714c   none           null      local

$ docker network inspect frontend-net --format 'name={{.Name}} driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
name=frontend-net driver=bridge subnet=172.18.0.0/16
```

Each new network gets its own `/16` from the `172.16.0.0/12` RFC 1918 block —
`frontend-net` took `172.18.0.0/16`, and `backend-net` and `db-net` took
`172.19.0.0/16` and `172.20.0.0/16`. That is the same private range I documented
in [Part 03](../03-networking/README.md), now visible in practice.

### Why user-defined networks and not the default bridge

Containers on a **user-defined** bridge get automatic DNS resolution by container
name, so `ping backend` works. The default `bridge` network has no such DNS — that
is why the deprecated `--link` flag once existed. User-defined networks also give
real isolation, which is exactly what this task is designed to demonstrate.

### Creating the containers

```bash
$ docker run -d --name frontend --network frontend-net alpine:latest sleep infinity
$ docker run -d --name backend  --network frontend-net alpine:latest sleep infinity
$ docker network connect backend-net backend
$ docker run -d --name database --network backend-net \
    -e MYSQL_ROOT_PASSWORD=root123 -e MYSQL_DATABASE=testdb mysql:8.0
$ docker network connect db-net database
```

`sleep infinity` keeps the alpine containers alive — a container lives exactly as
long as its PID 1, and alpine's default command would exit immediately.

**`docker run` accepts only one `--network`,** so the second and third memberships
have to come from `docker network connect` after the container exists. That is the
single most important mechanical detail in this task.

### Proof that `backend` is on two networks

```bash
$ docker inspect backend --format '{{range $n,$c := .NetworkSettings.Networks}}{{$n}} -> {{$c.IPAddress}}{{"\n"}}{{end}}'
backend-net -> 172.19.0.2
frontend-net -> 172.18.0.3
```

One container, **two interfaces, two addresses on two different subnets**. And
from the networks' point of view:

```bash
frontend-net   : frontend backend
backend-net    : database backend
db-net         : database
```

`backend` appears in two lists; `frontend` and `database` in one each.

### Test 1 — `frontend` → `backend` (same network, SUCCEEDS)

```bash
$ docker exec frontend ping -c 3 backend
PING backend (172.18.0.3) 56(84) bytes of data.
64 bytes from backend.frontend-net (172.18.0.3): icmp_seq=1 ttl=64 time=0.125 ms
64 bytes from backend.frontend-net (172.18.0.3): icmp_seq=2 ttl=64 time=0.212 ms
64 bytes from backend.frontend-net (172.18.0.3): icmp_seq=3 ttl=64 time=0.095 ms

--- backend ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2060ms
rtt min/avg/max/mdev = 0.095/0.144/0.212/0.049 ms
```

The reply address is reported as **`backend.frontend-net`** — Docker's DNS
qualifies the name with the network it was resolved on. That tells me *which*
network the resolution used, which becomes important in Test 4. Round-trip times
around **0.1 ms** confirm both containers are on the same virtual bridge.

### Test 2 — `backend` → `database` (same network, SUCCEEDS)

```bash
$ docker exec backend ping -c 3 database
PING database (172.19.0.3) 56(84) bytes of data.
64 bytes from database.backend-net (172.19.0.3): icmp_seq=1 ttl=64 time=0.139 ms
...
3 packets transmitted, 3 received, 0% packet loss, time 2030ms

$ docker exec backend nc -zv database 3306
Connection to database (172.19.0.3) 3306 port [tcp/mysql] succeeded!

$ docker exec backend nslookup database
Server:		127.0.0.11
Address:	127.0.0.11#53

Non-authoritative answer:
Name:	database
Address: 172.19.0.3
```

Three different proofs at three layers: ICMP reachability, a real **TCP**
connection to MySQL on 3306, and the DNS resolution underneath.

Note `database.backend-net` — `backend` reached the database over `backend-net`,
resolving `172.19.0.3`, even though the database also has an address on `db-net`.
Docker resolved the name on the network the two containers actually share.

`nslookup` reveals the mechanism: the resolver is **`127.0.0.11`**, Docker's
embedded DNS server, injected into every container on a user-defined network.

### Test 3 — `frontend` → `database` (no shared network, FAILS)

```bash
$ docker exec frontend ping -c 2 database
ping: database: Name does not resolve
[exit: 2]

$ docker exec frontend nslookup database
Server:		127.0.0.11
Address:	127.0.0.11#53

** server can't find database: NXDOMAIN
[exit: 1]
```

Running the same test with Alpine's **BusyBox** ping gives the canonical wording
of the same failure:

```bash
$ docker exec frontend busybox ping -c 2 database
ping: bad address 'database'
[exit: 1]

$ docker exec frontend sh -c 'which ping; ping -V 2>&1 | head -1'
/bin/ping
ping from iputils 20250605
```

Both messages describe the identical fault; only the wording differs, because
installing `iputils` for the reachability tests replaced BusyBox's `ping` with the
iputils one. BusyBox says `bad address`, iputils says `Name does not resolve`.
Worth knowing, because the phrase you search for depends on which binary answered.

**This is the mark-earning detail, and getting the explanation right matters more
than the failure itself.**

The error is `Name does not resolve` — a **DNS failure, not a routing failure**.
`nslookup` confirms it precisely: `NXDOMAIN`, meaning the name does not exist at
all as far as this container's resolver is concerned.

Docker's embedded DNS server at `127.0.0.11` only publishes the names of
containers that **share a network with the requester**. Because `frontend` and
`database` have no network in common, the name never resolves — and therefore
**not a single packet is ever sent**. There is no timeout, no "destination
unreachable", no dropped ICMP. The connection attempt fails before any network
traffic occurs.

That distinction is the whole point. A routing failure would look like a timeout
or an unreachable message. A DNS failure looks like this. Reading the error
correctly tells you which layer to investigate.

This is segmentation working exactly as designed, and it is why `backend` —
sitting on both networks — is the only path between the tiers.

### Test 4 — connect, prove it works, disconnect, prove it fails again

This is the strongest available evidence, because it flips the behaviour in both
directions with a single variable changed.

```bash
$ docker network connect db-net frontend
$ docker exec frontend ping -c 2 database
PING database (172.20.0.2) 56(84) bytes of data.
64 bytes from database.db-net (172.20.0.2): icmp_seq=1 ttl=64 time=0.073 ms
64 bytes from database.db-net (172.20.0.2): icmp_seq=2 ttl=64 time=0.192 ms

--- database ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1006ms

$ docker network disconnect db-net frontend
$ docker exec frontend ping -c 2 database
ping: database: Name does not resolve
[exit: 2]
```

Nothing changed except network membership — no restart, no configuration edit, no
DNS flush. Adding `frontend` to `db-net` made the name resolvable; removing it
made it unresolvable again.

One detail worth pointing out: after connecting, the resolved address is
**`172.20.0.2`** (`database.db-net`), not the `172.19.0.3` that `backend` saw.
`frontend` and `database` now share `db-net`, so the name resolved to the
database's address *on that* network. The same container name resolves to
different addresses depending on which network the asker is on — which is exactly
what "DNS scoped to shared networks" means in practice.

---

## Task 2 — Host networking

With `--network host` the container shares the host's network namespace: no NAT,
no port publishing, no isolation. Binding port 80 in the container **is** binding
port 80 on the host.

```bash
# Note: NO -p flag. Host networking does not use port publishing.
$ docker run -d --name apache-host --network host httpd:2.4

$ docker ps --filter name=apache-host --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES         IMAGE       PORTS
apache-host   httpd:2.4
```

**The empty `PORTS` column is itself the evidence.** Every other container in this
project shows something like `0.0.0.0:8083->80/tcp`. This one shows nothing,
because there is no mapping to describe — there is no NAT boundary to cross.

### Verifying from inside the host namespace

On macOS "the host" is the Docker Desktop Linux VM, not the Mac. Host networking
is a Linux kernel feature, so the technically correct place to test it is inside
that namespace. A throwaway container that also uses `--network host` shares the
same namespace, so its `localhost` **is** the Apache container:

```bash
$ docker run --rm --network host alpine:latest \
    sh -c 'apk add --no-cache curl >/dev/null && curl -si http://localhost:80 | head -8'
HTTP/1.1 200 OK
Date: Fri, 04 Sep 2026 17:36:19 GMT
Server: Apache/2.4.68 (Unix)
Last-Modified: Fri, 07 Nov 2025 08:23:08 GMT
ETag: "bf-642fce432f300"
Accept-Ranges: bytes
Content-Length: 191
Content-Type: text/html

$ docker run --rm --network host alpine:latest \
    sh -c 'apk add --no-cache iproute2 >/dev/null && ss -tulnp | grep ":80 "'
tcp   LISTEN 0      511                *:80               *:*
```

`HTTP/1.1 200 OK` from `Apache/2.4.68`, and a listening socket on `*:80` in that
namespace. Host networking is genuinely working.

To make the evidence unmistakably mine rather than a stock welcome page, I replaced
the served file:

```bash
$ docker cp /tmp/host-index.html apache-host:/usr/local/apache2/htdocs/index.html
$ docker run --rm --network host alpine:latest \
    sh -c 'apk add --no-cache curl >/dev/null && curl -s http://localhost:80'
<h1>Hello from Apache on the HOST network (port 80)</h1>
```

### From macOS itself — not reachable, and that is expected

```bash
$ curl -si --max-time 8 http://localhost:80 | head -5
(no output)
```

This is the documented macOS behaviour, not a fault. Docker Desktop's automatic
port forwarding into the VM applies to **published** (`-p`) ports. A
host-networked container publishes nothing, so there is no forwarding rule for
Docker Desktop to install, and `localhost:80` on the Mac does not reach into the
VM. Both results are recorded: reachable inside the VM namespace, not reachable
from macOS.

### Bridge versus host

| Aspect | Bridge (default) | Host |
|---|---|---|
| Network namespace | Its own, isolated | Shared with the host |
| Port publishing | Required (`-p`) | Not applicable |
| Container IP | Private, e.g. `172.18.0.3` | None of its own |
| Performance | Slight NAT overhead | Native |
| Port conflicts | Isolated per container | Two containers cannot both bind 80 |
| Container-name DNS | Yes, on user-defined networks | No |
| On macOS | Works transparently | "Host" is the Docker VM, not the Mac |

The `PORTS` column difference is the concrete expression of this whole table: a
bridge container **must** show a mapping because NAT is translating, and a host
container **cannot**, because nothing is being translated.

The row about port conflicts is demonstrated elsewhere in this project: `java-app`
and `multistage-app` both run applications on port 8080 *internally* with no
conflict at all, because each has its own namespace — only the host side of a
mapping has to be unique.

---

## Task 3 — Bind mount

```bash
$ docker run -d --name nginx-bind -p 8090:80 \
    -v "$PWD/html":/usr/share/nginx/html:ro nginx:alpine
```

### Three rules for `-v`

1. **The host path must be absolute.** `-v ./html:/...` is interpreted as a
   *named volume* called `./html`, not a bind mount. Hence `"$PWD/html"`.
2. **Quote the path** — macOS home directories can contain spaces.
3. **`:ro` mounts read-only.** A static site never needs write access from the
   container.

### Verifying the mount actually arrived

Before trusting `curl`, I checked that the file really reached the container — an
empty directory inside the container is the classic symptom of a host path that
Docker Desktop is not sharing:

```bash
$ docker exec nginx-bind cat /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Bind Mount Demo</title></head>
<body style="font-family:sans-serif;text-align:center;padding-top:60px">
  <h1>Hello students</h1>
</body></html>

$ docker inspect nginx-bind --format '{{range .Mounts}}{{.Type}}  {{.Source}} -> {{.Destination}} (ro={{not .RW}}){{end}}'
bind  /Users/thrishaldoma/devops-homework/07-docker-network-volume/bind-mount-demo/html -> /usr/share/nginx/html (ro=true)

$ curl -s http://localhost:8090
  <h1>Hello students</h1>
```

`Type` is `bind`, the source is the real host path, and `ro=true` confirms
read-only. Screenshot: [`../screenshots/07-bind-before.png`](../screenshots/07-bind-before.png)

### Live propagation — edited on the host, no restart

```bash
$ docker ps --filter name=nginx-bind --format '{{.Names}}: {{.Status}}'
nginx-bind: Up 20 seconds

# edit html/index.html on the macOS host. NO docker restart. NO rebuild.

$ curl -s http://localhost:8090
<html><head><meta charset="utf-8"><title>Bind Mount Demo - Updated</title></head>
<body style="font-family:sans-serif;text-align:center;padding-top:60px">
  <h1>Hello students - UPDATED without restarting the container!</h1>
  <p>Edited on the macOS host at: 23:07:14</p>
</body></html>
```

### Proving the container was never restarted

The uptime string alone is weak evidence, because two readings a few seconds apart
can print the same rounded value. So I took a later reading *and* asked Docker
directly:

```bash
$ docker ps --filter name=nginx-bind --format '{{.Names}}: {{.Status}}'
nginx-bind: Up About a minute

$ curl -s http://localhost:8090 | grep -o 'Hello students[^<]*'
Hello students - UPDATED without restarting the container!

$ docker inspect nginx-bind --format 'StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}}'
StartedAt=2026-09-04T17:36:53.348588597Z RestartCount=0
```

Three facts together are conclusive: uptime **advanced** from 20 seconds to about
a minute rather than resetting, `RestartCount` is **0**, and `StartedAt` is a
single unchanged timestamp from before the edit — while the served content is the
edited version. The container has run continuously across the change.

Screenshot after the edit:
[`../screenshots/07-bind-after.png`](../screenshots/07-bind-after.png)

This is why bind mounts are the standard tool for local development: the container
sees host filesystem changes immediately, with no image rebuild in the loop.

---

## Named volume, for contrast

```bash
$ docker volume create site-data
$ docker run -d --name nginx-vol -p 8091:80 -v site-data:/usr/share/nginx/html nginx:alpine
$ docker exec nginx-vol sh -c 'echo "<h1>From a named volume</h1>" > /usr/share/nginx/html/index.html'
$ curl -s localhost:8091
<h1>From a named volume</h1>

# DESTROY the container entirely, then create a new one on the same volume
$ docker rm -f nginx-vol
$ docker run -d --name nginx-vol -p 8091:80 -v site-data:/usr/share/nginx/html nginx:alpine
$ curl -s localhost:8091
<h1>From a named volume</h1>

$ docker volume inspect site-data --format '{{.Mountpoint}}'
/var/lib/docker/volumes/site-data/_data
```

The content survived complete destruction and recreation of the container. The
data's lifecycle is tied to the **volume**, not the container.

Note the mountpoint: `/var/lib/docker/volumes/site-data/_data`. That path exists
inside the Docker VM, **not** on the Mac — which is precisely why a named volume is
opaque from the host, and why I had to write into it via `docker exec` rather than
with a text editor.

| Aspect | Bind mount | Named volume |
|---|---|---|
| Location | Any path you choose on the host | Managed by Docker inside its VM |
| Host visibility | Ordinary files, editable directly | Opaque; go through Docker |
| Created automatically | No — the path must exist | Yes, on first use |
| Portability | Tied to host paths | Portable across hosts |
| Performance on Docker Desktop | Crosses the VirtioFS boundary; slower for large trees | Native to the VM; faster |
| Best for | Local development, live-editing config or source | Databases, production persistence |

---

## Task 4 — Overlay networks

### What it is

A **bridge** network spans one Docker host. An **overlay** network spans many,
presenting containers on different physical machines with a single flat layer-2
network: they get addresses from the overlay's subnet and reach each other by name
as if they shared a switch.

### How it works

The **data plane** uses **VXLAN encapsulation** — each container's Ethernet frame
is wrapped in a UDP packet on port **4789**, sent to the host holding the
destination container, and unwrapped there. The **control plane** is the swarm's
distributed store, which gossips the container-name → IP → host mapping to every
node so that DNS and routing stay consistent as containers start, stop and move.
Every service gets an overlay DNS entry, and requests are load-balanced across
replicas by the routing mesh. `--opt encrypted` wraps the VXLAN traffic in IPsec.

| Port | Protocol | Purpose |
|---|---|---|
| 2377 | TCP | Swarm cluster management (managers only) |
| 7946 | TCP + UDP | Node-to-node discovery and gossip |
| 4789 | UDP | VXLAN overlay data plane |

### Driver comparison

| Driver | Scope | Summary |
|---|---|---|
| `bridge` | Single host | Default. Private subnet plus NAT; name DNS on user-defined networks |
| `host` | Single host | No isolation — shares the host namespace |
| `none` | Single host | Loopback only; total isolation |
| `overlay` | **Multi-host** | VXLAN tunnel across a swarm |
| `macvlan` | Single host | Own MAC and an IP on the physical LAN |
| `ipvlan` | Single host | Like macvlan but shares the host MAC |

### Use cases

Swarm services whose replicas are scheduled across nodes but must still reach each
other by name; multi-host microservices without manual port publishing; scaling
out by adding a node whose containers join the same logical network automatically;
high availability, where a replacement container keeps the same service name and
DNS entry; and cluster-wide segmentation by environment or tier.

### Single-node demonstration

The machine was **not** already in a swarm, so it was safe to initialise one:

```bash
$ docker info --format '{{.Swarm.LocalNodeState}}'
inactive

$ docker swarm init
$ docker network create -d overlay --attachable my-overlay

$ docker network inspect my-overlay --format 'driver={{.Driver}} scope={{.Scope}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
driver=overlay scope=swarm subnet=10.0.1.0/24

$ docker run -d --name ov1 --network my-overlay alpine sleep infinity
$ docker run -d --name ov2 --network my-overlay alpine sleep infinity

$ docker exec ov1 ping -c 3 ov2
PING ov2 (10.0.1.4): 56 data bytes
64 bytes from 10.0.1.4: seq=0 ttl=64 time=0.149 ms
64 bytes from 10.0.1.4: seq=1 ttl=64 time=0.170 ms
64 bytes from 10.0.1.4: seq=2 ttl=64 time=0.189 ms

--- ov2 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
```

**The visible fingerprint of an overlay network is in that inspect output**, and
it differs from every bridge network in this project on two counts:

- **`scope=swarm`**, not `local` — the network is a cluster-wide object stored in
  the swarm's distributed database, not a local bridge.
- **`subnet=10.0.1.0/24`**, not `172.x` — overlays are allocated from
  `10.0.0.0/8`, matching the RFC 1918 table in [Part 03](../03-networking/README.md)
  where that block is noted as Docker overlay space.

`--attachable` is what allowed plain `docker run` containers to join; without it,
an overlay network accepts only swarm **services**.

Cleanup was complete, and only because this run created the swarm in the first
place:

```bash
$ docker rm -f ov1 ov2
$ docker network rm my-overlay
$ docker swarm leave --force
$ docker info --format '{{.Swarm.LocalNodeState}}'
inactive
```

Had the machine already been in a swarm, the demo would have been skipped and only
the research documented — leaving someone else's cluster is not an acceptable side
effect of a homework exercise.

---

## Final state

[`final-state.txt`](./final-state.txt) captures `docker ps`, `docker network ls`,
`docker volume ls` and the `backend` memberships at the end of the phase.

---

## Files in this folder

| Path | Contents |
|---|---|
| `bind-mount-demo/html/index.html` | The bind-mounted page, edited live during the test |
| `final-state.txt` | `docker ps` / `network ls` / `volume ls` / memberships |
| [`../logs/07-network-volume.log`](../logs/07-network-volume.log) | Full raw transcript of every command |
| [`../screenshots/07-bind-before.png`](../screenshots/07-bind-before.png) | Bind mount serving "Hello students" |
| [`../screenshots/07-bind-after.png`](../screenshots/07-bind-after.png) | Same container, updated content, never restarted |
