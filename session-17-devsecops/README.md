# Session 17 — Complete CI/CD & DevSecOps

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Repository:** <https://github.com/thrishaldoma/devops-homework>
**Pipeline:** [DevSecOps](../../actions/workflows/devsecops.yml) · **Image:** `ghcr.io/thrishaldoma/devsecops-demo`

Every scanner below produced **real findings** — locally and in CI. Transcripts in
[`logs/`](./logs), screenshots in [`screenshots/`](./screenshots).

---

## The pipeline

```
Code ─► Unit Tests ─┬─► SAST (bandit + CodeQL) ─┐
                    ├─► SCA (pip-audit) ────────┤
                    └─► Secret Scan (gitleaks) ─┤
                                                 ▼
                                     Docker Build + Image Scan (trivy)
                                                 ▼
                                         ╔═══════════════╗
                                         ║ SECURITY GATE ║
                                         ╚═══════╤═══════╝
                                                 ▼
                                   Push ghcr.io ─► Deploy to Kubernetes
```

All 9 jobs green:

```
✓ main DevSecOps · 37644683660
✓ Secret scanning: gitleaks  7s    ✓ Unit tests          12s
✓ SCA: pip-audit            29s    ✓ SAST: CodeQL      1m00s
✓ SAST: bandit              25s    ✓ Image scan: trivy 1m46s
✓ Security gate              4s    ✓ Push to ghcr.io     33s
✓ Deploy to Kubernetes     1m21s
```

**Registry:** published to **ghcr.io** using the built-in `GITHUB_TOKEN`, so the
pipeline needs no user-managed registry secret at all — one less credential to
rotate or leak. (The course reference pushes to Docker Hub with a `DOCKERHUB_TOKEN`.)

**Deployment:** a real `kind` cluster is created in CI, the image is loaded, and
the app is verified by HTTP:

```
deployment "session17-python" successfully rolled out
pod/session17-python-67fbf9d4fd-hjtq6   1/1   Running   10.244.0.5   chart-testing-control-plane
pod/session17-python-67fbf9d4fd-vb4zr   1/1   Running   10.244.0.6   chart-testing-control-plane
{"app":"DevSecOps Dashboard","status":"running","version":"2.0.0", ...}
```

📄 [`logs/03-pipeline-run.txt`](./logs/03-pipeline-run.txt) · 📸 [`03-pipeline-run.png`](./screenshots/03-pipeline-run.png)

---

## The security controls, and what each actually found

### Secret scanning — gitleaks → **4 findings**

```
kubernetes-secret-yaml   session-12-ingress-configmaps-secrets/04-full-demo/secret.yaml:7
generic-api-key          session-12-ingress-configmaps-secrets/04-full-demo/secret.yaml:15
kubernetes-secret-yaml   session-12-ingress-configmaps-secrets/02-secret/db-secret.yaml:7
generic-api-key          session-12-ingress-configmaps-secrets/02-secret/db-secret.yaml:15
```

The scanner caught **precisely the anti-pattern Session 12's own Task 5 warns
about** — base64 Secrets committed to Git — in this very repository. The values are
throwaway lab credentials, but gitleaks is right about the *pattern*.

**Triage, not suppression.** [`security/.gitleaks.toml`](./security/.gitleaks.toml)
allowlists those two paths with a written justification. Proven still live with a
canary:

```
with config, clean tree          -> no leaks found
with config + planted canary     -> leaks found: 1      <-- still catches new ones
without config + canary          -> leaks found: 5      <-- confirms the scope
```

> A side lesson: my first canary used AWS's *documented example key* and wasn't
> flagged, because gitleaks allowlists well-known doc keys by default. Testing a
> scanner with a sample key from the docs will tell you it's broken when it isn't.

### SCA — pip-audit → **the same scan gave two different answers**

```
locally:   click 8.1.8   PYSEC-2026-2132   fix: 8.3.3
in CI:     No known vulnerabilities found
```

Neither run is wrong. `requirements.txt` pins only `Flask==3.1.3`; Flask depends on
`click>=8.1.3`, so the version is resolved **at install time**. My machine had
`click 8.1.8` cached; the CI runner resolved `click 8.5.0`.

**Without a lockfile, an SCA scan describes the machine it ran on, not the
application.** Two engineers get two answers, and so does production. The fix is a
fully-pinned lockfile (`pip-compile`, `Pipfile.lock`, `poetry.lock`) so the
resolved tree — and therefore the scan result — is reproducible.

Note also that nothing in `requirements.txt` mentions `click`. That is the whole
point of SCA: your dependency *tree* is much bigger than your dependency *list*.

### SAST — bandit + CodeQL

Two tools because they look for different things: bandit pattern-matches known
insecure Python idioms; CodeQL does dataflow analysis to find taint reaching a
sink. Both upload SARIF to the repository's Security tab.

### Image scanning — trivy → **44 HIGH, 0 CRITICAL**

```
Total: 44 (HIGH: 44, CRITICAL: 0)
```

Scanned both my hardened image and the course's reference Dockerfile: **identical
counts**. The findings are inherited `python:3.12-slim` Debian CVEs
(`perl-base`, `util-linux`, `zlib`) marked `fix_deferred` — there is nothing to
upgrade to. Most image findings are inherited, and the lever is choosing a smaller
base (distroless, alpine), not patching your own code.

### The security gate

```
Fixable CRITICAL image vulnerabilities: 0
Security gate PASSED
```

**Policy: block on *fixable* CRITICALs only** (`ignore-unfixed: true`). Failing on
44 unfixable HIGHs would block every build forever, and a gate that always fails
teaches the team to bypass it — worse than no gate. A useful gate is one whose
failure is always actionable.

📄 [`logs/01-local-security-scans.txt`](./logs/01-local-security-scans.txt) · 📸 [`01-local-security-scans.png`](./screenshots/01-local-security-scans.png)

---

## Hardening: what the scanners *couldn't* tell me

The CVE counts for my image and the course's reference image are identical. The
real differences are configuration, and no vulnerability scanner reports them.

| | Course reference | This image |
|---|---|---|
| user | **root** | `appuser` (uid 10001) |
| server | `python app/app.py` — Flask dev server with **`debug=True`** | `gunicorn`, 2 workers |
| tests | not run during build | run in the builder stage |
| runtime contents | app + pytest + build tooling | app only |

`debug=True` exposes the Werkzeug debugger — an interactive Python console reachable
over HTTP, i.e. **remote code execution**. Running that as root in a container is
about as bad as a web app gets, and `trivy image` reports none of it.

### The Kubernetes side, verified enforced

[`app-src/k8s/deployment.yaml`](./app-src/k8s/deployment.yaml) adds
`runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ["ALL"]`, `seccompProfile`,
probes and resource limits. Declaring them is not the same as enforcing them, so:

```
$ kubectl exec deploy/session17-python -- id
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)

$ kubectl exec deploy/session17-python -- touch /app/evil
touch: cannot touch '/app/evil': Read-only file system

$ kubectl exec deploy/session17-python -- touch /tmp/ok
/tmp is writable (emptyDir), as gunicorn needs
```

And the app still works:

```
{"status":"healthy","uptime_seconds":22.07}
{"app":"DevSecOps Dashboard","python_version":"3.12.14","status":"running"}
```

📄 [`logs/02-hardened-k8s-deploy.txt`](./logs/02-hardened-k8s-deploy.txt) · 📸 [`02-hardened-k8s-deploy.png`](./screenshots/02-hardened-k8s-deploy.png)

---

## Supply-chain hardening of the pipeline itself

A security review of my own first version flagged two issues, both fixed:

**1. Unpinned third-party actions.** A tag like `@v3` is mutable — whoever controls
the action can repoint it at malicious code that then runs with your token. Every
third-party action is now pinned to a 40-character commit SHA:

```yaml
uses: aquasecurity/trivy-action@a9c7b0f06e461e9d4b4d1711f154ee024b8d7ab8 # v0.36.0
uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9       # v3
uses: docker/build-push-action@10e90e3645eae34f1e60eeb005ba3a3d33f178e8  # v6
uses: helm/kind-action@0025e74a8c7512023d06dc019c617aa3cf561fde          # v1.10.0
```

**2. Over-broad token permissions.** `packages: write` at workflow level gave every
job — including the ones running third-party scanners — a token that could push to
the registry. Now read-only by default, widened per job:

```
workflow      contents: read
sast-bandit   contents: read, security-events: write   (SARIF only)
sast-codeql   contents: read, security-events: write   (SARIF only)
push-image    contents: read, packages: write          (the only registry writer)
```

> Fixing the trivy pin also surfaced that the tag I had written, `0.28.0`, does not
> exist — the tags are `v`-prefixed. That job would have failed regardless.

---

## The run that failed first

```
X main DevSecOps · 37644256881
X Secret scanning: gitleaks in 7s
✓ SAST: CodeQL   ✓ SCA: pip-audit   ✓ SAST: bandit   ✓ Unit tests
```

**Root cause:** CI downloaded gitleaks **8.21.2** while the config was authored
against **8.30.1**. The older binary does not understand the `[[allowlists]]` array
syntax, **silently ignored the allowlist**, and failed on the 4 accepted findings.
Pinning the scanner version fixed it.

The failure mode is the interesting part: a scanner that silently ignores its own
config is more dangerous than one that errors. Here it failed loudly, but the same
version skew could just as easily have disabled a *rule* and let a real secret
through with a green check. **Pin your scanners like you pin your dependencies.**

---

## Index

| Path | Contents |
|---|---|
| [`app-src/`](./app-src) | Flask app, tests, hardened Dockerfile, k8s manifests |
| [`security/.gitleaks.toml`](./security/.gitleaks.toml) | triage config with written justification |
| [`reference/`](./reference) | the course's original Dockerfile, Deployment and workflow, for comparison |
| [`.github/workflows/`](./.github/workflows) | reference copy of the pipeline |
| [`../.github/workflows/devsecops.yml`](../.github/workflows/devsecops.yml) | **the live workflow** |
| [`04-sast/`](./04-sast) · [`05-sca/`](./05-sca) · [`06-secret-scanning/`](./06-secret-scanning) · [`07-container-image-scanning/`](./07-container-image-scanning) · [`08-security-gates/`](./08-security-gates) | course notes per control |

## Reproducing

```bash
cd session-17-devsecops
gitleaks dir ../ --config security/.gitleaks.toml --redact --no-banner
python3 -m pip_audit -r app-src/requirements.txt
docker build -t devsecops-demo:local app-src
trivy image --severity HIGH,CRITICAL --ignore-unfixed devsecops-demo:local
kubectl apply -f app-src/k8s/
```
