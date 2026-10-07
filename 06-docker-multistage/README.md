# Part 06 — Multi-Stage Build on Port 8080

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Host:** macOS 26.6.2 (arm64) + Docker Engine 29.7.2

---

## Source of the Dockerfile

The three project files — `Dockerfile`, `package.json` and `server.js` — come from
the course reference repository, at
`session6-7-docker/multi-stage-dockerfile/`. The repository was downloaded as a
**tarball with `curl`**, never cloned, so no `.git` directory was introduced into
this deliverable:

```bash
$ curl -sSL "https://github.com/Nency-Ravaliya/devops-heros/archive/refs/heads/main.tar.gz" -o repo.tgz
$ tar xzf repo.tgz
$ find "$REF" -name ".git" | wc -l
0
```

Its `LICENSE` and any `.DS_Store` files were deliberately not copied.

## One edit to the source

The task requires the page to display **"Hello World from Docker multi-stage
build"**. The reference `server.js` sent a slightly different string, so I
normalised it to match the requirement word for word:

```bash
# BSD sed on macOS needs the explicit empty -i argument
$ sed -i '' 's|Hello World from Docker Multi-Stage Build!|Hello World from Docker multi-stage build|' server.js

$ grep -n "Hello World" server.js
7:  res.send("<h1>Hello World from Docker multi-stage build</h1>");
```

That is the only change made to the reference material.

---

## The Dockerfile, instruction by instruction

```dockerfile
# -------------------------
# Stage 1: Build
# -------------------------
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

# -------------------------
# Stage 2: Production
# -------------------------
FROM node:24-alpine AS production
WORKDIR /app
COPY --from=builder /app/package*.json ./
RUN npm install --omit=dev
COPY --from=builder /app/server.js ./
EXPOSE 3000
CMD ["npm", "start"]
```

| Instruction | What it does and why |
|---|---|
| `FROM node:24-alpine AS builder` | Starts the first stage and **names** it `builder`. The name is what lets a later stage reference it. |
| `WORKDIR /app` | Sets the working directory, creating it if needed. All later relative paths resolve from here. |
| `COPY package*.json ./` | Copies only the manifests first. The glob catches both `package.json` and `package-lock.json`. |
| `RUN npm install` | Installs **all** dependencies, including dev ones. Because only the manifests have been copied so far, this layer is cached and reused unless the manifests themselves change. |
| `COPY . .` | Now brings in the application source. Source edits invalidate only this layer and later ones, not the `npm install` above it. |
| `FROM node:24-alpine AS production` | **Starts a brand-new image.** Everything in stage 1 is discarded unless explicitly copied forward. This line is the whole mechanism. |
| `COPY --from=builder /app/package*.json ./` | Pulls the manifests across from the first stage by name. |
| `RUN npm install --omit=dev` | Reinstalls **production dependencies only**, so dev tooling never enters the final image. |
| `COPY --from=builder /app/server.js ./` | Copies just the one file actually needed at runtime. |
| `EXPOSE 3000` | Documents the listening port. It is metadata only — it does **not** publish anything. |
| `CMD ["npm", "start"]` | The default command. In exec form, so the process gets PID 1 and receives signals directly rather than being wrapped in a shell. |

The key idea is that `COPY --from=builder` is a deliberate allow-list. Anything
not named on one of those lines — the dev dependencies, the npm cache, any
intermediate build output — simply does not exist in the final image.

---

## Build output

```bash
$ docker build -t multistage-hello:v1 .
#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 468B done
...
```

Full unedited build transcript is in
[`../logs/06-multistage.log`](../logs/06-multistage.log).

## Running it on port 8080 — and why the mapping matters

```bash
$ lsof -nP -iTCP:8080 -sTCP:LISTEN || echo '8080 is free'
8080 is free

$ docker run -d --name multistage-app -p 8080:3000 multistage-hello:v1
```

**The `-p 8080:3000` is the detail most easily got wrong.** The format is always
`-p HOST:CONTAINER`:

- the application inside the container listens on **3000** (set in `server.js`)
- the requirement is that it be reachable on host port **8080**
- therefore the mapping is `-p 8080:3000`

Writing `-p 8080:8080` would map host 8080 to container port 8080, where nothing
is listening, and the page would never load — with no error at container start to
hint at why.

`docker logs` confirms which port the app itself bound:

```bash
$ docker logs multistage-app

> docker-hello-world@1.0.0 start
> node server.js

Server running on port 3000
```

Note that the application reports **3000**, not 8080. The container is unaware
that its port has been republished; the translation happens entirely outside it.

## Application output

```bash
$ curl -s localhost:8080 | grep -o 'Hello World[^<]*'
Hello World from Docker multi-stage build
```

The exact required string. Full response with headers:

```bash
$ curl -i --max-time 10 localhost:8080
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: text/html; charset=utf-8
...
<h1>Hello World from Docker multi-stage build</h1>
```

## The `docker ps` evidence the task requires

```bash
$ docker ps --filter publish=8080 --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES            IMAGE                 STATUS          PORTS
multistage-app   multistage-hello:v1   Up 15 seconds   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp

$ docker port multistage-app
3000/tcp -> 0.0.0.0:8080
3000/tcp -> [::]:8080
```

**`0.0.0.0:8080->3000/tcp` is the proof.** Read it as: on all host interfaces,
port 8080 forwards to container port 3000. `docker port` states the same mapping
from the container's side. Both IPv4 and IPv6 are published.

### Screenshots

| Evidence | File |
|---|---|
| The page in a browser | [`../screenshots/06-multistage-browser.png`](../screenshots/06-multistage-browser.png) |
| `docker ps` showing port 8080 | [`../screenshots/06-docker-ps-8080.png`](../screenshots/06-docker-ps-8080.png) |

The `docker ps` screenshot was produced by writing the **real captured output**
into a minimal HTML file and rendering it with the same headless-browser helper
used for the web pages. An agent has no visible terminal window to photograph, and
this approach is both honest — the text is genuine command output, reproduced in
the log — and far more legible than a photograph of a window would be.

---

## Proving the benefit — multi-stage versus single-stage

I built a deliberately naive single-stage equivalent for comparison
([`Dockerfile.singlestage`](./Dockerfile.singlestage)):

```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install          # ALL dependencies, including dev
COPY . .                 # everything, including any junk in the context
EXPOSE 3000
CMD ["npm", "start"]
```

Real measured sizes:

```bash
$ docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|stage-hello'
REPOSITORY          TAG             SIZE
multistage-hello    v1              243MB
singlestage-hello   v1              249MB
```

| Aspect | Single-stage (249 MB) | Multi-stage (243 MB) |
|---|---|---|
| Final size | 249 MB | **243 MB** (−6 MB) |
| Dev dependencies | Present in the image | Removed — `--omit=dev` in stage 2 |
| Source-code exposure | Whole build context copied via `COPY . .` | Only `server.js` copied forward |
| Build caching | Source edits invalidate the install layer | Install layer cached independently |
| Attack surface | Build tooling and caches remain | Only the runtime and one source file |
| Pull time | Larger transfer for every deploy | Smaller |

### Being honest about the size saving

**6 MB is a modest saving, and it is worth saying why rather than overselling it.**
Both stages here use the *same* `node:24-alpine` base image, so the final image
still carries the entire Node runtime. The only things eliminated are the
dev-dependency tree and the build cache.

The layer breakdown confirms how little of the image is actually mine:

```bash
$ docker history multistage-hello:v1 --human --format 'table {{.Size}}\t{{.CreatedBy}}' | head -8
SIZE      CREATED BY
0B        CMD ["npm" "start"]
0B        EXPOSE [3000/tcp]
12.3kB    COPY /app/server.js ./ # buildkit
9.45MB    RUN /bin/sh -c npm install --omit=dev # buil…
45.1kB    COPY /app/package*.json ./ # buildkit
8.19kB    WORKDIR /app
0B        CMD ["node"]
```

My application contributes **12.3 kB** of source and **9.45 MB** of production
dependencies (essentially all of it Express). The remaining ~231 MB is the
`node:24-alpine` base. That is why the multi-stage saving is bounded here: you
cannot strip what you still need.

**Multi-stage pays off in proportion to how different the build and runtime
environments are.** Two contrasts from this same run make the point:

- **The React app in Phase 5** built with `node:20-alpine` (194 MB) and shipped on
  `nginx:alpine` — final image **102 MB**, with the entire Node toolchain
  discarded, because static files need no JavaScript runtime.
- **The Java app in Phase 5** compiled on `eclipse-temurin:21-jdk-alpine`
  (556 MB) and shipped on `21-jre-alpine` (287 MB) — roughly **270 MB** saved,
  because running bytecode does not require a compiler.
- The classic extreme is a Go binary copied into `scratch`, dropping from hundreds
  of megabytes to under 15, since a statically linked binary needs no OS at all.

Here the bases are identical, so only the dependency tree differs. The *technique*
is demonstrated correctly; the magnitude simply depends on the language.

---

## Task 3 — Three application types running simultaneously

The Phase 5 containers were still running, so this phase's container joins them as
the evidence:

```bash
$ docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES            IMAGE                 STATUS          PORTS
multistage-app   multistage-hello:v1   Up 32 seconds   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp
nginx-app        nginx-hello:v1        Up 4 minutes    0.0.0.0:8083->80/tcp, [::]:8083->80/tcp
react-app        react-hello:v1        Up 4 minutes    0.0.0.0:3001->80/tcp, [::]:3001->80/tcp
apache-app       apache-hello:v1       Up 4 minutes    0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
java-app         java-hello:v1         Up 4 minutes    0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
python-app       python-hello:v1       Up 4 minutes    0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp
nodejs-app       nodejs-hello:v1       Up 4 minutes    0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
linux-lab        linux-lab:v1          Up 21 minutes
```

All answering at the same time:

```
port 3000  -> Hello World from Node.js + Docker!
port 5001  -> Hello World from Python + Docker!
port 8081  -> Hello World from Java + Docker!
port 8080  -> Hello World from Docker multi-stage build
```

Four different language runtimes — Node, Python, Java and the multi-stage Node
image — serving concurrently on four distinct host ports.

Note `java-app` maps `8081->8080` while `multistage-app` maps `8080->3000`. Both
containers have an application on port 8080 *internally* with no conflict
whatsoever, because each container has its own network namespace. Only the **host**
side of a mapping has to be unique. This is the single most useful practical
consequence of container network isolation, and having two containers in this
state at once demonstrates it directly.

---

## What I learned

The mechanism that makes multi-stage builds work is simply that **each `FROM`
starts a new image**, and `COPY --from=` is the only bridge between them. That
turns image construction from "install things and hope the result is small" into
an explicit allow-list of what reaches production.

The port mapping was the more immediately practical lesson. `-p HOST:CONTAINER`
is easy to state and easy to invert under pressure, and inverting it produces a
container that starts perfectly, reports success in its own logs, and serves
nothing — a failure with no error message anywhere. The habit worth keeping is to
read `docker port` or the `PORTS` column after starting anything, rather than
trusting that the flag was written the right way round.

The size comparison taught me to be sceptical of the standard multi-stage claim.
The technique is genuinely valuable, but the headline savings quoted in tutorials
come from cases where the runtime base differs from the build base. Measuring both
images rather than assuming produced a 6 MB answer where I had expected far more,
and understanding *why* it was small taught me more than a large number would
have.

---

## Files in this folder

| File | Contents |
|---|---|
| `Dockerfile` | The reference multi-stage build (`builder` → `production`) |
| `Dockerfile.singlestage` | Naive single-stage equivalent, for the size comparison only |
| `package.json` | From the reference repository, unmodified |
| `server.js` | From the reference repository, with the output string normalised |
| [`../logs/06-multistage.log`](../logs/06-multistage.log) | Full raw transcript |
