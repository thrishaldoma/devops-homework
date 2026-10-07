# Session 16 — CI/CD & GitHub Actions

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Repository:** <https://github.com/thrishaldoma/devops-homework>
**Pipelines:** [CI](https://github.com/thrishaldoma/devops-homework/actions/workflows/ci.yml) · [CD](https://github.com/thrishaldoma/devops-homework/actions/workflows/cd.yml)

Unlike the other sessions, this one could not be proven locally — the deliverable
is *"screenshots of successful pipeline execution"*. These are **real GitHub
Actions runs**, not simulations. Transcripts in [`logs/`](./logs).

---

## CI vs CD

| | **CI — Continuous Integration** | **CD — Continuous Delivery/Deployment** |
|---|---|---|
| Question | "does this change break anything?" | "can this change safely reach users?" |
| Trigger | every push / PR | only a **successful** CI run on `main` |
| Produces | test results, a build artifact, an image | a deployed, running release |
| On failure | block the merge | block the deploy |

The division is enforced here by `workflow_run` — CD literally cannot start unless
CI concluded `success`. That is visible in the run history below: the failing
commit's CD shows **`skipped`**.

---

## The application

A small Python calculator (from the course's `10-final-cicd-pipeline`) plus a
production-shaped container image.

| File | Purpose |
|---|---|
| [`app/calculator.py`](./app/calculator.py) | add / subtract / multiply / divide |
| [`tests/test_calculator.py`](./tests/test_calculator.py) | 5 pytest cases incl. divide-by-zero |
| [`Dockerfile`](./Dockerfile) | multi-stage: tests run **inside** the build |
| [`build.sh`](./build.sh) | produces the `build/` artifact |
| [`pytest.ini`](./pytest.ini) | `pythonpath = .` so tests need no `sys.path` hacks |

The Dockerfile runs the test suite in the **builder** stage, so an image can only
exist if the tests passed:

```
$ docker build --progress=plain --no-cache --target builder -t calculator:builder .
#12 0.204 5 passed in 0.01s
```

The runtime stage then copies only the app, runs as **uid 10001 (non-root)**, and
carries no pytest or build tooling.

---

## Pipeline design

```
            ┌──> Lint ──────────┐
  Unit tests├──> Build artifact ├──> Docker build        (CI)
            └──> Secret scan ───┘
                                        │ workflow_run: success
                                        ▼
            Package image ──> Deploy staging ──> Deploy production   (CD)
```

`test` is a single gate; `lint`, `build` and `secret-scan` then fan out in
parallel because none depends on another. `docker` fans back in via
`needs: [lint, build, security-scan]`. Total CI wall-clock: **~1 minute**.

### Concepts, and where each is used

| Concept | Where |
|---|---|
| **Workflow** | [`ci.yml`](./.github/workflows/ci.yml), [`cd.yml`](./.github/workflows/cd.yml) |
| **Job** | `test`, `lint`, `build`, `security-scan`, `docker` |
| **Step** | the numbered actions inside each job |
| **Runner** | `ubuntu-latest`, GitHub-hosted |
| **Trigger** | `push`, `pull_request`, `workflow_dispatch`, `workflow_run` |
| **Artifact** | `test-results`, `calculator-build`, `container-image` |
| **Secrets** | `${{ secrets.* }}` — none needed; the registry push is out of scope |
| **Environments** | `staging`, `production` — where approval gates attach |
| **Caching** | `cache: pip` and `type=gha` for Docker layers |

---

## Task — real pipeline execution

```
$ gh run list --limit 6
completed  success  CD   workflow_run  37642850562  1m14s
completed  success  CI   push          37642427639  2m9s
completed  success  CI   push          37641213194  1m4s
completed  skipped  CD   workflow_run  37640922980  2s       <-- gate held
completed  failure  CI   push          37640856575  29s      <-- first run
```

### Run 1 — **failed**, and that is the useful part

```
X main CI · 37640856575
✓ Unit tests in 14s
X Lint in 7s

app/calculator.py:3:1:  E302 expected 2 blank lines, found 1
app/calculator.py:26:1: W293 blank line contains whitespace
tests/test_calculator.py:5:1: E402 module level import not at top of file
```

The linter found genuine defects in the course's source. **CD for that commit was
`skipped`** — the `workflow_run` gate did its job and a failing build never reached
a deploy stage.

I fixed the **code**, not the linter:
- stripped trailing whitespace and corrected blank-line spacing;
- removed the `sys.path.insert(...)` from the test module — the real cause of
  `E402` — and replaced it with `pythonpath = .` in `pytest.ini`, which is how
  pytest is meant to solve this.

### Run 2 — green

```
✓ main CI · 37642427639
✓ Unit tests in 10s     ✓ Secret scan in 6s    ✓ Build artifact in 5s
✓ Lint in 10s           ✓ Docker build in 23s
```

### CD — triggered automatically by that success

```
✓ main CD · 37642850562
✓ Package image in 36s
✓ Deploy to staging in 22s
✓ Deploy to production in 5s
```

### Artifacts actually produced

```
calculator-build   1,005 bytes       (CI)
test-results         381 bytes       (CI, uploaded with if: always())
container-image   47,155,180 bytes   (CD)
```

`test-results` uses `if: always()` so results publish even when tests fail —
otherwise the one run you most need to inspect is the one with no artifact.

📄 [`logs/02-pipeline-runs.txt`](./logs/02-pipeline-runs.txt) · 📸 [`02-pipeline-runs.png`](./screenshots/02-pipeline-runs.png)

---

## Two container bugs the pipeline exposed

Neither was visible by reading the code; both needed the image to actually run.

### 1. `ENTRYPOINT` swallowed the smoke test — CD hung for 11 minutes

```
ENTRYPOINT ["python", "-m", "app.calculator"]
```

With `ENTRYPOINT`, `docker run <image> python -c "..."` **appends** the arguments
rather than replacing them, so the smoke test started the *interactive* calculator
instead of its own command. The staging job sat for 11 minutes before being
cancelled. Reproduced locally:

```
$ docker run --rm calculator:ci-test python -c "print('hi')"
Calculator Application              <-- not 'hi'
```

**Fix:** `CMD` instead of `ENTRYPOINT`, which is overridden cleanly. Verified:

```
$ docker run --rm calculator:ci-test python -c "...print('override OK, add(10,5) =', add(10,5))"
override OK, add(10,5) = 15
```

### 2. The app spun forever on EOF

With no TTY, `input()` raises `EOFError` — which the calculator's catch-all
`except Exception` swallowed, looping instantly and forever. A container that
never exits and burns CPU is exactly what hung the job. Now:

```
$ docker run --rm -i calculator:ci-test < /dev/null
Goodbye!
container exit code: 0
```

**The general lesson:** `ENTRYPOINT` vs `CMD` and EOF handling look like trivia
until a CI job hangs on them. A bounded smoke test (`timeout 60 docker run`) turns
a 6-hour hung job into a 60-second failure.

📄 [`logs/01-local-verification.txt`](./logs/01-local-verification.txt) · 📸 [`01-local-verification.png`](./screenshots/01-local-verification.png)

> **One more operational note.** A `docker build --no-cache` piped through my log
> helper wrote a **29GB** file, because BuildKit's default renderer emits
> continuous progress frames. `--progress=plain` produced the same information in
> **3,966 bytes**. Never let a progress-rendering command write into a file you
> intend to keep.

---

## Index

| Path | Contents |
|---|---|
| [`app/`](./app) · [`tests/`](./tests) | application and test suite |
| [`Dockerfile`](./Dockerfile) · [`.dockerignore`](./.dockerignore) | multi-stage image |
| [`.github/workflows/`](./.github/workflows) | reference copies of the two workflows |
| [`../.github/workflows/`](../.github/workflows) | **the live workflows** GitHub executes |

> Workflows only run from `.github/workflows/` at the **repository root**. The
> copies inside this folder exist so the session is self-contained to read.

## Reproducing

```bash
cd session-16-github-actions
docker build -t calculator:ci-test .        # runs the tests inside the build
docker run --rm calculator:ci-test python -c "from app.calculator import add; print(add(10,5))"
gh workflow run ci.yml                      # trigger CI by hand
gh run watch
```
