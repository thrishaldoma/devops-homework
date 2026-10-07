# Part 05 — Six Dockerised Hello World Apps

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Host:** macOS 26.6.2 (arm64) + Docker Engine 29.7.2

Six web applications, each in its own folder with its own Dockerfile, all built,
run and verified over HTTP, with all six containers running **simultaneously**.

---

## Port plan

| Folder | Stack | Container port | Host port | Image tag | Final size |
|---|---|---|---|---|---|
| `nodejs-app` | Node 20 + Express | 3000 | 3000 | `nodejs-hello:v1` | 210 MB |
| `python-app` | Python 3.11 + Flask | 5000 | **5001** | `python-hello:v1` | 231 MB |
| `java-app` | Temurin 21, JDK→JRE multi-stage | 8080 | 8081 | `java-hello:v1` | 286 MB |
| `Apache-app` | httpd 2.4 | 80 | 8082 | `apache-hello:v1` | 205 MB |
| `React-app` | Vite build served by Nginx | 80 | 3001 | `react-hello:v1` | **102 MB** |
| `nginx-app` | nginx:alpine | 80 | 8083 | `nginx-hello:v1` | 102 MB |

### Why host port 5001 and not 5000

On macOS Monterey and later, the **AirPlay Receiver** service binds port 5000.
The Flask container still listens on 5000 *internally*; only the host side of the
mapping moves, via `-p 5001:5000`. Nothing in the application changed.

Port 8080 was deliberately left free during this phase — Phase 6 needs it for the
multi-stage build.

### A port conflict that did occur

Port 3000 was occupied at the start of the run by an unrelated `next-server`
development server (confirmed with `lsof -nP -iTCP:3000 -sTCP:LISTEN`). It was
stopped so the playbook's port plan could be used exactly as written, with no
deviation anywhere in these READMEs. Recorded as Issue 2 in
[`../logs/ISSUES.md`](../logs/ISSUES.md).

---

## The apps

### 1. Node.js + Express — `nodejs-app/`

`server.js` serves an HTML page reporting the container hostname and Node version.
The Dockerfile copies `package*.json` **before** the source:

```dockerfile
COPY package*.json ./
RUN npm install --omit=dev
COPY server.js ./
```

That ordering is a caching decision, not cosmetic. Docker caches each layer keyed
on its inputs, so as long as the manifests are unchanged the `npm install` layer is
reused and only the final `COPY` re-runs when I edit `server.js`. Copying
everything first would re-install dependencies on every source edit.

`app.listen(PORT, "0.0.0.0", ...)` binds all interfaces — binding `127.0.0.1`
would make the app unreachable from the host regardless of `-p`.

### 2. Python + Flask — `python-app/`

**The reference app was deliberately replaced.** The course repository's
`session6-7-docker/python-app/app.py` is a single `print()` statement. That writes
one line to the container log and the process then exits, so the container stops
immediately and there is no webpage at all — it cannot satisfy "verify Hello World
is displayed on a webpage". I substituted a minimal Flask application that serves
a real HTTP response.

```python
if __name__ == "__main__":
    # 0.0.0.0 is essential: 127.0.0.1 would only be
    # reachable from inside the container
    app.run(host="0.0.0.0", port=5000)
```

Flask's own startup output is worth reading:

```
 * Serving Flask app 'app'
 * Debug mode: off
WARNING: This is a development server. Do not use it in a production deployment.
```

That warning is correct and I am leaving it visible rather than hiding it. For
this exercise the development server is the right choice; a production image would
put Gunicorn or uWSGI in front, because Flask's built-in server is
single-threaded and has no process supervision.

### 3. Java — `java-app/`

No Maven or Gradle. The JDK's built-in `com.sun.net.httpserver` keeps this to one
source file, which also makes a genuine **multi-stage** build possible:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS build
COPY App.java .
RUN javac App.java

FROM eclipse-temurin:21-jre-alpine
COPY --from=build /src/*.class ./
```

Stage 1 needs the **JDK** because it has to compile. Stage 2 only needs to *run*
bytecode, so it uses the **JRE**. The measured difference in the base images:

| Base image | Size |
|---|---|
| `eclipse-temurin:21-jdk-alpine` | 556 MB |
| `eclipse-temurin:21-jre-alpine` | 287 MB |

The final `java-hello:v1` is **286 MB**. Shipping the JDK would have meant 556 MB,
so the second stage saved roughly **270 MB** — and, more importantly, removed the
compiler and development tooling from the runtime image entirely.

`docker logs java-app` confirms it started: `Java server running on port 8080`.

### 4. Apache — `Apache-app/`

```dockerfile
FROM httpd:2.4
COPY index.html /usr/local/apache2/htdocs/index.html
```

**Document roots are the most common cause of "I still see the default page".**
httpd serves from `/usr/local/apache2/htdocs/`, while nginx serves from
`/usr/share/nginx/html/`. Copying to the wrong one silently leaves the stock
welcome page in place, and nothing errors.

### 5. React — `React-app/`

Built with Vite and served by Nginx from a **two-stage** image:

```dockerfile
FROM node:20-alpine AS build
RUN npm install
RUN npm run build          # Vite writes to /app/dist

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

This is the most dramatic multi-stage saving of the six. The build stage needs the
whole Node toolchain plus `node_modules`; the runtime stage needs only static
files and a web server:

| | Size |
|---|---|
| `node:20-alpine` build stage (before `node_modules`) | 194 MB |
| `nginx:alpine` runtime base | 102 MB |
| **Final `react-hello:v1`** | **102 MB** |

The final image is the *same size as plain nginx* — the compiled bundle is small
enough not to move the number. The entire Node toolchain was discarded.

The project was written by hand from the playbook's Appendix B rather than
scaffolded with `npm create vite`, to avoid an interactive prompt and to keep
`node_modules` out of the deliverable. `npm install` still runs inside the Docker
build, where dependencies belong. Recorded as Issue 3.

`.dockerignore` is **not optional** here:

```
node_modules
dist
Dockerfile
*.log
```

Without it, `COPY . .` would upload any local `node_modules` into the build
context — hundreds of megabytes, and potentially architecture-incompatible native
modules.

### 6. Nginx — `nginx-app/`

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

`daemon off;` is essential. nginx daemonises by default, so its main process would
exit immediately and Docker would consider the container finished. A container
lives exactly as long as its PID 1, so the server must stay in the foreground.

---

## Build and run

All six were built and started with one helper, then verified:

```bash
build_run() {   # folder image container hostport ctrport
  docker rm -f "$3" >/dev/null 2>&1 || true
  docker build -t "$2" "$1"
  docker run -d --name "$3" -p "$4:$5" "$2"
}
build_run nodejs-app  nodejs-hello:v1  nodejs-app  3000 3000
build_run python-app  python-hello:v1  python-app  5001 5000
build_run java-app    java-hello:v1    java-app    8081 8080
build_run Apache-app  apache-hello:v1  apache-app  8082 80
build_run React-app   react-hello:v1   react-app   3001 80
build_run nginx-app   nginx-hello:v1   nginx-app   8083 80
```

The `docker rm -f ... || true` line makes the whole phase **idempotent** — it can
be re-run from the start without "name already in use" errors.

### All six running simultaneously

```
$ docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
NAMES        IMAGE             STATUS              PORTS
nginx-app    nginx-hello:v1    Up About a minute   0.0.0.0:8083->80/tcp, [::]:8083->80/tcp
react-app    react-hello:v1    Up About a minute   0.0.0.0:3001->80/tcp, [::]:3001->80/tcp
apache-app   apache-hello:v1   Up 2 minutes        0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
java-app     java-hello:v1     Up 2 minutes        0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
python-app   python-hello:v1   Up 2 minutes        0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp
nodejs-app   nodejs-hello:v1   Up 2 minutes        0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
```

The `PORTS` column is the evidence that matters. Read `0.0.0.0:8081->8080/tcp` as
**host 8081 forwards to container 8080** — the format is always
`-p HOST:CONTAINER`. Note how `java-app` maps 8081→8080 and `python-app` maps
5001→5000: the container port is whatever the application binds, and the host port
is what I chose to avoid collisions.

### Image sizes

```
$ docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep hello
apache-hello    v1    205MB
java-hello      v1    286MB
nginx-hello     v1    102MB
nodejs-hello    v1    210MB
python-hello    v1    231MB
react-hello     v1    102MB
```

The two smallest are the two that end in `nginx:alpine`. Alpine-based images win
on size because they use musl libc and BusyBox instead of glibc and GNU coreutils.

---

## HTTP verification — the primary evidence

```
port 3000  -> Hello World from Node.js + Docker!
port 5001  -> Hello World from Python + Docker!
port 8081  -> Hello World from Java + Docker!
port 8082  -> Hello World from Apache + Docker!
port 3001  -> NO RESPONSE
port 8083  -> Hello World from Nginx + Docker!
```

### Why React shows `NO RESPONSE` — and why that is not a failure

Five apps are **server-rendered**, so the string is in the HTML body and `curl`
finds it. React is **client-rendered**: nginx serves only a 325-byte shell, and
the heading is injected into the DOM by JavaScript at runtime.

```bash
$ curl -s localhost:3001
<!doctype html>
<html lang="en">
  <head><title>React + Docker</title>
    <script type="module" crossorigin src="/assets/index-DqWUiq_Y.js"></script></head>
  <body><div id="root"></div></body>
</html>
```

nginx's own access log shows the request **succeeded**:

```bash
$ docker logs react-app | tail -1
192.168.65.1 - - [04/Sep/2026:17:28:31 +0000] "GET / HTTP/1.1" 200 325 "-" "curl/8.7.1" "-"
```

Status `200`, 325 bytes. The string exists — inside the JS bundle:

```bash
$ docker run --rm react-hello:v1 sh -c 'grep -o "Hello World from React + Docker!" /usr/share/nginx/html/assets/*.js'
Hello World from React + Docker!
```

So I verified it with an instrument that *can* execute JavaScript:

```bash
$ chrome --headless --dump-dom http://localhost:3001
<div id="root"><div style="font-family: sans-serif; text-align: center; padding-top: 60px;">
<h1>Hello World from React + Docker!</h1>
<p>Built with Vite, served by Nginx from a multi-stage image</p></div></div>
```

The rendered DOM contains the exact required string, and
[`../screenshots/05-react.png`](../screenshots/05-react.png) shows it in a browser.
**No change was made to the application, because nothing was wrong with it.**

The general lesson is that a verification method has to match the thing being
verified. A `curl | grep` health check would have failed this perfectly healthy
app — a genuinely common CI mistake with single-page applications. The right check
for an SPA asserts on the HTTP status and the presence of the asset bundle, or
drives a real browser. Recorded as Issue 8.

---

## Screenshots

All six captured with headless Chrome, which is deterministic and needs no screen
permissions:

| App | Screenshot |
|---|---|
| Node.js | [`../screenshots/05-nodejs.png`](../screenshots/05-nodejs.png) |
| Python | [`../screenshots/05-python.png`](../screenshots/05-python.png) |
| Java | [`../screenshots/05-java.png`](../screenshots/05-java.png) |
| Apache | [`../screenshots/05-apache.png`](../screenshots/05-apache.png) |
| React | [`../screenshots/05-react.png`](../screenshots/05-react.png) |
| Nginx | [`../screenshots/05-nginx.png`](../screenshots/05-nginx.png) |

---

## Bonus — `docker-compose.yml`

[`docker-compose.yml`](./docker-compose.yml) builds and runs all six with a single
command:

```bash
docker compose up -d --build
```

**Do not run it while the individually-named containers are up** — they publish
the same host ports and the bind would fail with "address already in use". It is
shipped as a convenience for rebuilding everything at once, not as the method used
for the evidence above.

---

## Files in this folder

| Path | Contents |
|---|---|
| `nodejs-app/` | `package.json`, `server.js`, `Dockerfile`, `.dockerignore` |
| `python-app/` | `app.py`, `requirements.txt`, `Dockerfile` |
| `java-app/` | `App.java`, `Dockerfile` (JDK→JRE multi-stage) |
| `Apache-app/` | `index.html`, `Dockerfile` |
| `React-app/` | 5-file Vite project, `Dockerfile` (Node→Nginx multi-stage), `.dockerignore` |
| `nginx-app/` | `index.html`, `Dockerfile` |
| `docker-compose.yml` | All six services in one file |
| [`../logs/05-docker-apps.log`](../logs/05-docker-apps.log) | Full raw build, run and verification transcript |

Folder names reproduce the homework spec character for character, including the
inconsistent capitalisation of **`Apache-app`** and **`React-app`** against the
lowercase `nodejs-app`, `python-app`, `java-app` and `nginx-app`.

No `node_modules` or `dist` directory is left anywhere in the deliverable.
