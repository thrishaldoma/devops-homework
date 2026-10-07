# Observability — the three pillars

**Session 20, Task 2**

## Monitoring vs observability

They are not synonyms, and the difference decides what you can do at 3am.

| | **Monitoring** | **Observability** |
|---|---|---|
| Answers | "is the thing I predicted broken?" | "why is it broken, including in ways I never predicted?" |
| Built from | dashboards and alerts on **known** failure modes | high-cardinality telemetry you can query freely |
| Question shape | *closed* — "is CPU > 85%?" | *open* — "why are checkout requests from Android users in Mumbai slow?" |
| Fails when | the failure is one nobody anticipated | — |

Monitoring is a **subset** of observability. A system is observable when you can
answer new questions about its internals **without shipping new code** to collect
more data. If diagnosing an incident requires adding a log line and redeploying,
the system was not observable.

---

## Pillar 1 — Metrics

Numeric measurements sampled over time. Cheap to store, cheap to aggregate, ideal
for dashboards and alerts.

| Type | Meaning | Example |
|---|---|---|
| **Counter** | only increases | `http_requests_total` |
| **Gauge** | goes up and down | `node_memory_MemAvailable_bytes` |
| **Histogram** | bucketed distribution | `http_request_duration_seconds` |
| **Summary** | client-side quantiles | request latency |

Measured on this cluster:

```
192.168.49.2:9100   CPU busy:  2.86%     memory used: 39.27%
192.168.49.3:9100   CPU busy:  2.46%     memory used: 38.45%
```

**Strength:** tiny and fast — millions of series, queried in milliseconds.
**Limit:** **low cardinality only.** Each distinct label combination is a separate
time series, so a `user_id` label on a million users creates a million series and
will take Prometheus down. *What* is wrong, never *which request*.

### Always prefer histograms to averages

An average latency of 200ms is consistent with everyone getting 200ms, or with
95% getting 50ms and 5% getting 3 seconds. Alert on **p95/p99**, not the mean.

---

## Pillar 2 — Logs

Timestamped, usually textual records of discrete events.

**Structured logs** (JSON) beat free text, because they are queryable:

```json
{"ts":"2026-10-07T16:12:00Z","level":"error","msg":"payment declined",
 "order_id":"ord_8821","user_id":"u_42","trace_id":"4bf92f...","latency_ms":1840}
```

**Strength:** full detail of a single event — the *why*.
**Limit:** expensive at volume, and hard to aggregate across millions of lines.

In Kubernetes, containers write to stdout/stderr, the kubelet collects it, and
`kubectl logs` reads it. A node agent (Fluent Bit, Promtail) ships it to Loki or
Elasticsearch, because `kubectl logs` only sees the **current and previous**
container — once a pod is deleted, its logs are gone.

> **Session 14 found the failure mode that breaks this pillar entirely.** Two pods
> were `Running` with 0 restarts and `kubectl logs` returned *nothing* — Python
> buffers stdout when it is not a TTY, so the application's output never reached
> the container's stdout. The app was fine; the observability was broken, which is
> worse, because it blinds you precisely when you need it. Fix: `PYTHONUNBUFFERED=1`.

---

## Pillar 3 — Traces

A trace follows **one request across every service it touches**. Each hop is a
span, and spans carry a shared trace ID.

```
trace 4bf92f3577b34da6
├─ api-gateway        12ms
│  └─ auth-service     8ms
│     └─ redis         1ms
└─ order-service     1840ms          <-- the latency lives here
   ├─ postgres         14ms
   └─ payment-api    1801ms          <-- actually, here
```

**Strength:** the only pillar that answers *where* time goes in a distributed
system. Metrics say "checkout is slow"; traces say "the third-party payment API
is slow".
**Limit:** needs **instrumentation** in the application (OpenTelemetry), and is
usually **sampled** because tracing every request is prohibitive.

---

## How the three fit together

```
  METRIC   alert fires: checkout p99 latency > 2s
     │
     ▼
  TRACE    find a slow trace: 1801ms inside payment-api
     │
     ▼
  LOG      read that span's logs by trace_id: "payment declined, upstream timeout"
```

Metrics tell you **that** something is wrong and wake you up. Traces tell you
**where**. Logs tell you **why**. A `trace_id` propagated into your log lines is
what joins them — without it you are grepping by timestamp and guessing.

---

## Common tools

| Pillar | Open source | Managed |
|---|---|---|
| Metrics | **Prometheus**, VictoriaMetrics, Thanos | Datadog, CloudWatch, Grafana Cloud |
| Logs | **Loki**, Elasticsearch, Fluent Bit | Datadog, Splunk, CloudWatch Logs |
| Traces | **Jaeger**, Tempo, OpenTelemetry | Datadog APM, X-Ray, Honeycomb |
| Visualisation | **Grafana** | — |

**OpenTelemetry** is the vendor-neutral standard for emitting all three. Instrument
once against the OTel API and you can change backend without touching the app —
the main defence against observability vendor lock-in.

---

## Kubernetes observability specifics

| What | Where it comes from |
|---|---|
| Node CPU/memory/disk | **node-exporter** (DaemonSet — one per node, as in Session 10) |
| Container CPU/memory | **cAdvisor**, built into the kubelet |
| Object state (pods, deployments, PVCs) | **kube-state-metrics** |
| `kubectl top` | **metrics-server** — *not* a monitoring system |

**metrics-server vs Prometheus** is a common confusion. metrics-server keeps only
the **latest** value in memory to drive `kubectl top` and the HPA (Session 13).
It stores no history and cannot be queried. Prometheus scrapes and retains time
series. You need both, for different jobs.

Verified on this cluster — 11 scrape targets across 5 jobs:

```
kubernetes-api-servers        1 target
kubernetes-nodes              2 targets   (kubelet)
kubernetes-nodes-cadvisor     2 targets   (per-container metrics)
kubernetes-service-endpoints  5 targets   (kube-state-metrics, node-exporter, ...)
prometheus                    1 target    (itself)
```

### The golden signals

For any user-facing service, these four are the right starting point:

| Signal | Why |
|---|---|
| **Latency** | p95/p99, and split successful from failed requests |
| **Traffic** | requests/sec — context for everything else |
| **Errors** | rate of 5xx and of failed business outcomes |
| **Saturation** | how full the constrained resource is |

Alert on **symptoms users feel** (latency, errors), not on causes (CPU). High CPU
with healthy latency is not an incident; it is a well-utilised machine.
