# Issues Encountered and How They Were Handled

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097

This file is the honest record of everything that did not work first time during
the run, and what was done about it. It is required by Section 01.3 of the
execution playbook ("On failure: record, adapt, continue").

---

## Issue 1 — Docker was not installed on the host

**When:** Preflight (Section 02.2), before Phase 1.

**Detected by:**

```
$ command -v docker
(no output)
$ ls -d /Applications/Docker.app
ls: /Applications/Docker.app: No such file or directory
$ ls -la /var/run/docker.sock
ls: /var/run/docker.sock: No such file or directory
```

I also checked for every alternative container runtime (Colima, Podman, Lima,
nerdctl, OrbStack, Rancher Desktop) and found none. So this was not a PATH
problem — there was genuinely no container runtime on the machine.

**Why this mattered:** Docker Desktop is a hard prerequisite of the playbook.
Phases 1, 5, 6 and 7 run entirely in containers, and Phases 2 and 3 each have a
container half.

**Why I did not fix it myself:** Section 01.2 forbids installing system software
and forbids `sudo`, and says explicitly: "If you believe something is genuinely
missing, stop and ask." Installing Docker Desktop needs administrator rights.
So I stopped and asked, rather than breaking a hard constraint.

**Resolution:** The user chose to install Docker Desktop themselves. While
waiting, I completed every phase that has no Docker dependency (the folder tree
and tooling in Section 02, all of Phase 4, and the native macOS portions of
Phases 2 and 3) so that no time was lost.

---

## Issue 2 — Host port 3000 was already in use

**When:** Preflight (Section 02.2).

**Detected by:**

```
$ lsof -nP -iTCP:3000 -sTCP:LISTEN
COMMAND   PID         USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node    61460 thrishaldoma   13u  IPv6 0x2e46be9697232881      0t0  TCP *:3000 (LISTEN)
```

Port 3000 is the host port the playbook assigns to `nodejs-app`. I identified the
owner before touching it:

```
$ ps -o pid,ppid,user,etime,command -p 61460
  PID  PPID USER          ELAPSED COMMAND
61460 46606 thrishaldoma 03:48:24 next-server (v15.0.3)
```

It was a Next.js development server belonging to the user, running out of
`~/rl_epic/frontend` — not a container from this run.

**Resolution:** The playbook's documented fallback is to pick the next free port
and use it consistently. I initially planned to move `nodejs-app` to port 3002 on
that basis. The user then instructed me directly to stop the server and keep port
3000, so I sent it a graceful `SIGTERM` (not `SIGKILL`) and confirmed the port was
released and did not respawn. A dev server holds no unsaved state; it can be
restarted with `npm run dev` in `~/rl_epic/frontend`.

**Net effect on the deliverable:** none. Because port 3000 was freed, the port
plan in Section 7.1 is used exactly as written, with no deviation anywhere in the
READMEs. All eleven planned host ports (80, 3000, 3001, 5000, 5001, 8080, 8081,
8082, 8083, 8090, 8091) were confirmed free before Phase 5.

---

## Issue 3 — React app written by hand instead of scaffolded with Vite

**When:** Phase 5, App 5 (React).

**What the playbook offers:** Section 7.6 scaffolds the project with
`npm create vite@latest` inside a `node:20-alpine` container, and Appendix B
supplies a complete minimal five-file Vite project as the documented fallback,
with the instruction to "record which route was taken in ISSUES.md."

**Route taken:** the Appendix B hand-written route.

**Why I chose the fallback deliberately rather than after a failure:**

1. `npm create vite@latest` can block on an interactive template prompt. There is
   no terminal attached to an agent run, so an interactive prompt is an
   indefinite hang rather than a clean failure.
2. The scaffold route bind-mounts the deliverable folder into the container and
   runs `npm install` there, which writes `node_modules/` **into the deliverable**
   — several hundred megabytes that Gate 5 and `_tools/verify.sh` then both
   require to be deleted again. Avoiding it entirely is cleaner than creating it
   and cleaning up after it.

Dependencies are still installed by `npm install` **inside the Docker build**,
which is where they belong, so the image is built exactly as it would have been.
The five files are `package.json`, `index.html`, `vite.config.js`,
`src/main.jsx` and `src/App.jsx`, plus a `.dockerignore` listing `node_modules`
and `dist`.

`src/App.jsx` deliberately imports no CSS or asset file. Appendix A.4 notes that a
leftover import of a scaffold-generated asset that no longer exists is the most
common cause of a React container that builds but serves nothing.

---

## Issue 4 — Docker Desktop cannot start: Virtualization.framework failure

**When:** After Docker Desktop was installed, before Phase 1. This is the issue
that blocked the container-based phases.

**Symptom:** the Docker CLI worked, but the daemon never became reachable.

```
$ docker --version
Docker version 29.7.2, build a7dcaa6

$ docker info
Error response from daemon: Docker Desktop is unable to start

$ docker desktop status
Name                Value
Status              starting
```

`Status: starting` never advanced. It stayed there for more than sixteen minutes
across several launch attempts, with no Linux VM process ever appearing:

```
$ ps aux | grep -c 'Docker Desktop.app'   ->  0
$ ps aux | grep -c 'com.docker.virtualization'  ->  0
```

**A wrong first diagnosis, and how it was corrected.** My initial reading of
`~/Library/Group Containers/group.com.docker/settings-store.json` was that the
licence agreement had not been accepted, because the key `AcceptedLicense` read
as `None`. That conclusion was wrong: `AcceptedLicense` is simply not a key in
this version's settings schema, so absence proved nothing. Dumping the whole file
showed the licence had in fact been accepted:

```
DisplayedOnboarding = True
LicenseTermsVersion = 2
ShowInstallScreen   = False
RequireVmnetd       = False
DockerBinInstallPath = user
```

`RequireVmnetd = False` and `DockerBinInstallPath = user` also rule out a missing
privileged helper — this is a user-level install that needs no admin rights.

**Actual root cause,** from `com.docker.backend.log`:

```
NSLocalizedFailure       = "Internal Virtualization error.";
NSLocalizedFailureReason = "Failed to install Rosetta.";
Rosetta installation skipped due to unexpected error:
    Error Domain=VZErrorDomain Code=1
```

`VZErrorDomain Code=1` is `VZErrorInternal` — an internal failure inside Apple's
**Virtualization.framework**, which is the hypervisor Docker Desktop relies on to
run its Linux VM. Rosetta itself is present and healthy on the machine (`oahd`,
the Rosetta daemon, is running), so the missing-Rosetta message is a symptom
rather than the cause: the framework call that would have set up Rosetta inside
the VM failed because the VM could not be brought up at all. The backend process
then sat in a loop reporting:

```
cannot toggle VM OTel collector, backend is not running
```

This is a host-level incompatibility between Docker Desktop 4.89.0 and
macOS 26.6.2, not a problem with anything in this playbook or the deliverable.

**Why I did not work around it myself.** The two available fixes are changing
Docker Desktop's virtualization settings, and reinstalling or downgrading Docker
Desktop. Section 01.2 forbids both: "Do not change macOS settings, Docker Desktop
settings, or network configuration" and "Do not install ... any system software.
If you believe something is genuinely missing, stop and ask." So I reported the
finding with its evidence and asked the user how to proceed.

**Note on the Docker CLI path.** Docker Desktop installed its CLI to
`~/.docker/bin/docker` rather than `/usr/local/bin/docker`, because the
`/usr/local/bin` symlink needs administrator rights. `~/.docker/bin` is not on the
default `PATH`. Rather than modify the user's shell profile — which lies outside
`~/devops-homework` and is therefore out of scope under Section 01.2 — every
Docker command in this run prepends that directory to `PATH` for the duration of
that command only, leaving nothing behind on the machine.

---

### Resolution — switching the hypervisor to Docker VMM

With the user's explicit go-ahead to attempt a repair, I changed **one** setting,
after backing the file up first so the change was reversible.

Docker Desktop on Apple Silicon can run its Linux VM on either of two
hypervisors: Apple's **Virtualization.framework**, or Docker's own **Docker VMM**
(built on libkrun — confirmed present in the shipped binary, which exports
`krun.Engine`). The failing component was Apple's framework specifically, so the
targeted fix was to select the other one. In `settings-store.json`:

```json
"UseVirtualizationFramework": false,
"UseVirtualizationFrameworkRosetta": false
```

Setting `UseVirtualizationFramework` to `false` makes Docker Desktop use Docker
VMM instead of Apple's framework. The Rosetta flag was cleared at the same time
because Rosetta support is a feature *of* Apple's framework, so it is meaningless
once that framework is not in use — and its installation was the operation that
had been failing.

**Result — the daemon came up immediately:**

```
$ docker info --format 'server={{.ServerVersion}} arch={{.Architecture}} cpus={{.NCPU}} mem={{.MemTotal}}'
server=29.7.2 arch=aarch64 cpus=15 mem=8318844928
```

15 CPUs and 8.3 GB of memory, comfortably above the 4 CPU / 8 GB the playbook
asks for. All ten base images then pulled successfully on the first attempt.

The original `settings-store.json` is backed up outside the deliverable, so the
change can be reverted by restoring it and relaunching Docker Desktop. The only
practical consequence of running Docker VMM is that `--platform linux/amd64`
emulation via Rosetta is unavailable — irrelevant here, because every image this
playbook uses is multi-architecture and runs natively on `aarch64`.

**Correction to an earlier entry in this file.** An earlier version of this issue
stated that Docker Desktop was blocked waiting for its licence agreement to be
accepted. That was a misdiagnosis on my part, drawn from the key `AcceptedLicense`
reading as absent in the settings file. `AcceptedLicense` is not part of this
version's settings schema at all, so its absence was not evidence of anything.
Dumping the complete file showed `DisplayedOnboarding = true` and
`LicenseTermsVersion = 2` — the licence had already been accepted. The entry has
been rewritten above with the real cause and the log evidence for it.

---

## Issue 5 — Intermittent DNS failures on the host network

**When:** Phase 3, macOS host command lab.

**What happened:** on the first pass, two DNS tools failed for `github.com` while
other tools succeeded for the same name at the same time:

```
$ host github.com
;; connection timed out; no servers could be reached
[exit: 1]

$ nslookup github.com | tail -8
;; Got SERVFAIL reply from 100.129.160.1, trying next server
Server:		8.8.8.8
Address:	8.8.8.8#53
** server can't find github.com: SERVFAIL
```

Yet at the same time:

```
$ curl -sI --max-time 10 https://github.com | head -3
HTTP/2 200
$ nc -zv -G 5 github.com 443
Connection to github.com port 443 [tcp/https] succeeded!
```

**Investigation:** I re-probed both resolvers directly rather than assuming a
cause. Both answered correctly on the retry:

```
$ dig +short github.com A
20.207.73.82
$ dig @100.129.160.1 github.com A   ->  status: NOERROR, ANSWER: 1
$ dig @8.8.8.8 github.com A         ->  status: NOERROR, ANSWER: 1
$ dscacheutil -q host -a name github.com
name: github.com
ip_address: 20.207.73.82
```

**Conclusion:** this was a **transient** resolution failure, not DNS filtering and
not a misconfiguration. It is consistent with the packet loss measured in the same
session — `ping -c 4 8.8.8.8` reported **25.0% packet loss** with round-trip times
ranging 29.253–87.279 ms. On a lossy link a single UDP DNS query with no retry
budget fails while TCP connections, which retransmit, still succeed. `curl` also
benefits from macOS's already-cached resolver entry.

**Impact on the deliverable:** none. Both the failing first attempt and the
successful re-probe are kept in `logs/03-networking-macos.log`, because a
real intermittent fault and the reasoning that identified it are better evidence
than a clean log that hides it.

---

## Issue 6 — Intermittent DNS failures inside Docker as well

**When:** First container run after the daemon started.

The first `docker run` failed on name resolution, not on anything to do with the
image:

```
$ docker run --rm hello-world
docker: Error response from daemon: failed to resolve reference
"docker.io/library/hello-world:latest": failed to authorize:
... connecting to auth.docker.io:443: dial tcp: lookup auth.docker.io: no such host
```

The host itself resolved the same name correctly at that moment:

```
$ dig +short auth.docker.io A
auth.docker.io.cdn.cloudflare.net.
172.64.144.78
104.18.43.178
```

An immediate retry succeeded with no configuration change at all:

```
$ docker pull alpine:latest
Status: Downloaded newer image for alpine:latest
```

**Conclusion:** the same intermittent resolution fault already documented in
Issue 5, now visible through Docker's resolver rather than the host's. No
`daemon.json` DNS override was added, because nothing was actually
misconfigured — adding one would have masked a transient network fault behind a
permanent change to the user's Docker installation.

**Mitigation applied:** every image pull in this run is wrapped in a retry loop
(five attempts, five seconds apart) rather than assumed to succeed first time.
In the event all ten pulls did succeed on their first attempt once the daemon was
healthy.

---

---

## Issue 7 — Three commands failed inside the lab container, all from one root cause

**When:** Phase 1 Task 4 and Phase 3 command lab.

Three separate commands failed in ways that initially looked unrelated:

```
$ head -5 /etc/services
head: cannot open '/etc/services' for reading: No such file or directory
[exit: 1]

$ whois github.com | head -25
getaddrinfo(whois.verisign-grs.com): Servname not supported for ai_socktype

$ curl -sSI https://github.com
curl: (77) error setting certificate file: /etc/ssl/certs/ca-certificates.crt
```

**Investigation.** I checked what was actually installed rather than guessing:

```
$ ls -la /etc/ssl/certs/ca-certificates.crt
ls: cannot access '/etc/ssl/certs/ca-certificates.crt': No such file or directory
$ dpkg -l ca-certificates | tail -1
un  ca-certificates <none>  <none>  (no description available)
$ dpkg -l netbase | tail -1
un  netbase         <none>  <none>  (no description available)
```

`un` means "unknown" — never installed.

**Root cause — a single one for all three.** The lab image is built with
`apt-get install -y --no-install-recommends`. That flag is why the image contains
only 217 packages, but it also omitted two packages that nothing in my explicit
list formally depends on:

- **`ca-certificates`** ships the CA trust bundle. Without it `curl` cannot verify
  any TLS certificate, so every HTTPS request fails with error 77. The first
  attempt looked like it "returned nothing" only because `-s` suppresses the error
  message; re-running with `-sS` revealed it.
- **`netbase`** ships `/etc/services`, the service-name-to-port-number map. Without
  it `getaddrinfo()` cannot resolve the service name `whois` to port 43, which is
  exactly what "Servname not supported for ai_socktype" means. It also explains the
  `head /etc/services` failure in Task 4.

**Fixes applied, both inside the container only:**

```
$ apt-get install -y ca-certificates && update-ca-certificates
$ curl -sSI https://github.com | head -4
HTTP/2 200
date: Fri, 04 Sep 2026 17:22:52 GMT
content-type: text/html; charset=utf-8

$ whois -h whois.verisign-grs.com -p 43 github.com | head -6
   Domain Name: GITHUB.COM
   Registry Domain ID: 1264983250_DOMAIN_COM-VRSN
   Registrar WHOIS Server: whois.markmonitor.com
   Creation Date: 2007-10-09T18:20:50Z
   Registrar: MarkMonitor Inc.
```

For `whois` I passed `-p 43` explicitly, which bypasses the service-name lookup
entirely rather than installing another package — the smaller change. That port
was reachable all along, which is what isolated the fault to name resolution
rather than connectivity:

```
$ nc -zv -w 5 whois.verisign-grs.com 43
Connection to whois.verisign-grs.com (192.30.45.30) 43 port [tcp/*] succeeded!
```

**Note on scope.** These installs happened *inside the container*, not on the
macOS host, so Section 01.2's prohibition on installing host software is not
engaged. The playbook itself installs packages into containers in Phase 7
(`apk add iputils bind-tools netcat-openbsd`).

**Lesson recorded in the deliverable.** This is the genuine trade-off of
`--no-install-recommends`: it produced a much smaller image, but transferred to me
the responsibility for packages that are transitively useful rather than strictly
required. A production image intending to make HTTPS calls must list
`ca-certificates` explicitly.

---

## Issue 8 — The React app "failed" its HTTP check, but was working correctly

**When:** Phase 5, HTTP verification of the six apps.

Five of the six apps returned their Hello World string to `curl`. React did not:

```
port 3000  -> Hello World from Node.js + Docker!
port 5001  -> Hello World from Python + Docker!
port 8081  -> Hello World from Java + Docker!
port 8082  -> Hello World from Apache + Docker!
port 3001  -> NO RESPONSE
port 8083  -> Hello World from Nginx + Docker!
```

**This was not a fault.** Before changing anything I checked what the container was
actually serving:

```
$ curl -s localhost:3001
<!doctype html>
<html lang="en">
  <head>
    <title>React + Docker</title>
    <script type="module" crossorigin src="/assets/index-DqWUiq_Y.js"></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

nginx returned a complete, valid page — and its own access log confirms a
successful response, not an error:

```
$ docker logs react-app | tail -2
192.168.65.1 - - [04/Sep/2026:17:28:31 +0000] "GET / HTTP/1.1" 200 325 "-" "curl/8.7.1" "-"
```

Status **200**, 325 bytes. The playbook's suggested check also passed — the build
artefacts are present in the image:

```
$ docker run --rm react-hello:v1 ls -la /usr/share/nginx/html
drwxr-xr-x 2 root root 4096 Sep  4 17:28 assets
-rw-r--r-- 1 root root  325 Sep  4 17:28 index.html
```

And the expected string is present — inside the **JavaScript bundle**, not the HTML:

```
$ docker run --rm react-hello:v1 sh -c 'grep -o "Hello World from React + Docker!" /usr/share/nginx/html/assets/*.js'
Hello World from React + Docker!
```

**Root cause.** React is a **client-rendered** single-page application. The HTML
that nginx serves is only a 325-byte shell containing `<div id="root"></div>`; the
heading text is injected into the DOM by JavaScript when the page runs. `curl` is
an HTTP client, not a browser — it never executes JavaScript — so
`curl | grep 'Hello World'` cannot match this app no matter how healthy it is.
The other five apps are all server-rendered, which is why they matched.

**Correct verification.** I used a JavaScript-executing browser instead, which is
the right instrument for a client-rendered app:

```
$ chrome --headless --dump-dom http://localhost:3001
<div id="root"><div style="font-family: sans-serif; text-align: center; padding-top: 60px;">
<h1>Hello World from React + Docker!</h1>
<p>Built with Vite, served by Nginx from a multi-stage image</p></div></div>
```

The rendered DOM contains the exact required string, and
`screenshots/05-react.png` shows the heading rendered in the browser.

**What I took from this.** A verification method has to match the thing being
verified. A `curl | grep` health check that would have been declared a failure
here is a genuinely common CI mistake with SPAs — the fix is either to test the
rendered DOM with a real browser, or to assert on the HTTP status code and the
presence of the asset bundle rather than on body text. No change was made to the
application, because nothing was wrong with it.

---

## Issue 9 — Two resources needed cleanup that the playbook's teardown list did not name

**When:** Phase 8 teardown.

The playbook's Section 10.4 teardown list covers every container, image, network
and volume it tells you to create. Capturing the final state revealed two
resources created *indirectly*, which that list therefore does not mention:

```
$ docker network ls
NETWORK ID     NAME              DRIVER    SCOPE
5ebf59c865fa   docker_gwbridge   bridge    local        <-- not in the registry
...
$ docker volume ls
DRIVER    VOLUME NAME
local     5dd4dc399b4ac88690f6461903ca6df549cf01ce497c1741c27245526952f2bd
local     site-data
```

1. **`docker_gwbridge`** is created automatically by `docker swarm init` during the
   Phase 7 overlay demo, and is **not** removed by `docker swarm leave --force`.
2. The **anonymous volume** was created by the `mysql:8.0` container, because that
   image declares a `VOLUME` for `/var/lib/mysql` in its own Dockerfile. Docker
   allocates a randomly-named volume for it whenever one is not supplied
   explicitly.

**Both were removed,** because both were created by this run:

```
removed network docker_gwbridge
removed dangling volume 5dd4dc399b4ac88690f6461903ca6df549cf01ce497c1741c27245526952f2bd
```

The dangling volume was removed with `docker volume ls -qf dangling=true`, which
was safe **only because** the pre-run baseline in `logs/00-docker-baseline.log`
recorded zero pre-existing volumes on this machine. Had the user owned any
dangling volumes, that filter would have caught theirs too, and each would have
had to be removed by exact name instead.

**Verification.** The post-teardown state matches the pre-run baseline exactly:
0 containers, 0 volumes, and only the three default networks.

**Lesson.** A teardown list written from the commands you intend to run will miss
resources that images and subsystems create on your behalf. Capturing the state
*before* starting is what made the difference detectable at all — without
`00-docker-baseline.log` there would have been no way to distinguish "created by
this run" from "already the user's".
