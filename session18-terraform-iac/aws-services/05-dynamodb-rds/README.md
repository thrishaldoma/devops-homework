# DynamoDB & RDS — Database Services

**Session 18, Task 2.5**

Two managed database services that solve different problems. The choice is not
"which is better" but **"is my access pattern known in advance?"**

---

# Part 1 — DynamoDB (NoSQL)

A fully managed key-value and document store. No servers, no version upgrades,
single-digit millisecond reads at any scale.

## Data model

| Term | Relational equivalent |
|---|---|
| **Table** | table |
| **Item** | row (max 400 KB) |
| **Attribute** | column — but **schemaless**: every item can differ |

Only the key attributes are required; everything else varies per item.

## Keys — the single most important design decision

**Partition key (hash key)** — hashed to choose a physical partition.

**Sort key (range key)** — optional. Items sharing a partition key are stored
*sorted* by it, which is what enables range queries:

```
PK = "USER#1107"   SK = "ORDER#2026-01-15"
PK = "USER#1107"   SK = "ORDER#2026-02-02"
PK = "USER#1107"   SK = "PROFILE"
```

`Query(PK = "USER#1107", SK begins_with "ORDER#")` returns that user's orders,
sorted, in one request. This is **single-table design**: several entity types in
one table, distinguished by key prefix.

### Query vs Scan

| | Query | Scan |
|---|---|---|
| Reads | one partition | **the entire table** |
| Cost | proportional to results | proportional to **table size** |

**A `Scan` on a large table is almost always a design error.** If you need a
different access pattern, add a **Global Secondary Index** — a different key
schema over the same data.

### Choosing a good partition key

High cardinality, evenly accessed. A key like `status = "ACTIVE"` creates a **hot
partition**: all traffic hits one shard and throttles while the table looks idle.

## Capacity, consistency, features

- **On-demand** — pay per request, absorbs spikes. Start here.
- **Provisioned** — cheaper for steady, predictable load; supports auto-scaling.
- **Eventually consistent** reads (default, half price) vs **strongly consistent**.
- **Transactions** — ACID across items, with a cost multiplier.
- **DynamoDB Streams** — change data capture, commonly feeding a Lambda.
- **TTL** — automatic expiry of items; free deletes. Ideal for sessions and caches.

## Common use cases

- Session stores, shopping carts, user profiles.
- IoT / event ingestion at high write rates.
- **Terraform state locking** — the `dynamodb_table` beside an S3 backend. Exactly the problem the local state file in [`../../terraform-s3-demo/`](../../terraform-s3-demo) has: nothing stops two engineers applying at once.

---

# Part 2 — RDS (Relational)

Managed relational databases: AWS handles patching, backups, failover and
replication; you keep SQL, joins, and ACID transactions.

## Supported engines

**PostgreSQL**, **MySQL**, **MariaDB**, **Oracle**, **SQL Server**, and
**Aurora** (AWS's own MySQL/PostgreSQL-compatible engine with a distributed
storage layer — faster failover, storage that grows automatically).

## DB instances

Sized like EC2 (`db.t4g.medium`, `db.r6g.large`), with storage configured
separately (gp3 / io1, with optional autoscaling).

## Security

| Control | Practice |
|---|---|
| **Network** | **private subnets only** — `publicly_accessible = false` |
| **Security group** | inbound 5432/3306 from the *app* security group, never a CIDR |
| **Encryption at rest** | KMS. **Can only be enabled at creation** — retrofitting means a snapshot/restore cycle |
| **Encryption in transit** | enforce TLS (`rds.force_ssl = 1`) |
| **Credentials** | **Secrets Manager** with automatic rotation — not an env var, and certainly not in Git |
| **IAM auth** | token-based auth, no stored password at all |

> This is the Session 12 and Session 17 lesson again, one layer down: the
> database password should never be a committed literal. Secrets Manager is the
> AWS equivalent of the External Secrets Operator pattern.

## Backups

- **Automated backups** — daily snapshot plus transaction logs, giving
  **point-in-time recovery** to any second in the retention window (1–35 days).
  Retention `0` disables them; that is a common and costly default to leave.
- **Manual snapshots** — kept until you delete them, survive instance deletion.
- Always take a **final snapshot** on delete (`skip_final_snapshot = false`).

## Multi-AZ vs Read Replicas — frequently confused

| | **Multi-AZ** | **Read Replica** |
|---|---|---|
| Purpose | **availability** | **scale reads** |
| Replication | synchronous | asynchronous |
| Standby serves traffic? | **No** — it is idle | Yes, read-only |
| Failover | automatic, DNS swings (60–120s) | manual promotion |
| Cross-region | no | yes |

Multi-AZ is insurance; read replicas are capacity. **Neither is a backup** — both
faithfully replicate a `DROP TABLE`. Only snapshots and PITR protect against that.

## Common use cases

- Transactional application databases where joins and constraints matter.
- Reporting against a read replica so analytics never slow production.
- Aurora Serverless v2 for spiky or dev workloads.

---

# Choosing between them

```
Do you know your access patterns up front, and are they few and fixed?
│
├── YES, and you need massive scale / unpredictable traffic  ──► DynamoDB
│
└── NO - ad-hoc queries, joins, reporting, strong relational
          integrity, or an existing SQL application           ──► RDS
```

| | DynamoDB | RDS |
|---|---|---|
| Schema | flexible | fixed |
| Joins | none (denormalise) | yes |
| Scaling | horizontal, automatic | vertical + read replicas |
| Query flexibility | only via keys/indexes | any SQL |
| Ops burden | none | patching windows, sizing |

The honest summary: **DynamoDB trades query flexibility for scale.** If you
cannot list your access patterns before designing the table, you want SQL.
