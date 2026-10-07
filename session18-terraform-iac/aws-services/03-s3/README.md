# S3 — Simple Storage Service (Storage)

**Session 18, Task 2.3** — the service provisioned by
[`../../terraform-s3-demo/`](../../terraform-s3-demo), so everything here was
exercised in practice.

S3 is **object** storage, not a filesystem. You `PUT` and `GET` whole objects by
key; you cannot seek into one or append to it. That constraint is what buys
eleven nines of durability and effectively unlimited scale.

---

## Buckets and objects

| Term | Meaning |
|---|---|
| **Bucket** | the container. Name is **globally unique across all of AWS**, 3–63 chars, lowercase |
| **Object** | the data (up to 5 TB) plus metadata |
| **Key** | the object's full name, e.g. `invoices/2026/q1.pdf` |

There are **no real directories**. `invoices/2026/q1.pdf` is one flat key; the
console renders the slashes as folders. This is why "renaming a folder" means
copying every object under that prefix.

Our Terraform enforces the naming rule before AWS ever sees it:

```hcl
validation {
  condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
  error_message = "bucket_name must be 3-63 characters, lowercase alphanumeric or hyphens..."
}
```

---

## Storage classes

| Class | Use for | Retrieval |
|---|---|---|
| **Standard** | active data | instant |
| **Intelligent-Tiering** | unknown/changing access patterns | instant, auto-tiers |
| **Standard-IA** | infrequent but needs instant access | instant, higher per-GB read cost |
| **One Zone-IA** | reproducible data (thumbnails, caches) | instant, single AZ |
| **Glacier Instant** | archives needing instant access | instant |
| **Glacier Flexible** | backups | minutes–hours |
| **Glacier Deep Archive** | compliance, 7–10 year retention | up to 12 hours |

The trap: IA and Glacier classes have **minimum storage durations** (30/90/180
days) and per-request retrieval charges. Moving churny data to IA can cost *more*
than Standard.

---

## Versioning

```hcl
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration { status = "Enabled" }
}
```

Verified live:

```
$ curl -s 'http://localhost:4566/yatri-session18-demo?versioning'
<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>
```

With versioning on, a `DELETE` writes a **delete marker** rather than destroying
data — recoverable. It can be **suspended but never disabled**, and every version
is billed, which is why versioning and lifecycle rules belong together.

## Lifecycle policies

```hcl
rule {
  id     = "archive-then-expire"
  status = "Enabled"
  transition      { days = 30  storage_class = "STANDARD_IA" }
  transition      { days = 90  storage_class = "GLACIER" }
  expiration      { days = 365 }
  noncurrent_version_expiration { noncurrent_days = 30 }
}
```

That last line is the one people forget: without it, old versions accumulate
forever and the bill grows even though the "current" data looks small.

---

## Security — the part that matters most

**Public buckets are the classic cloud data breach.** Our Terraform blocks all
four public-access vectors:

```hcl
resource "aws_s3_bucket_public_access_block" "demo" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Encryption at rest**, always on and free with SSE-S3:

```hcl
rule {
  apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
}
```

| Option | When |
|---|---|
| **SSE-S3** (AES256) | default; AWS manages the key |
| **SSE-KMS** | you need an audit trail of key use, or key rotation control |
| **SSE-C** | you supply the key per request |
| **Client-side** | AWS must never see plaintext |

**Bucket policies** are resource-based, so they can grant cross-account access and
can enforce conditions identity policies cannot — e.g. refusing any non-TLS request:

```json
{ "Effect": "Deny", "Principal": "*", "Action": "s3:*",
  "Resource": "arn:aws:s3:::bucket/*",
  "Condition": { "Bool": { "aws:SecureTransport": "false" } } }
```

Prefer bucket policies and IAM over **ACLs** — ACLs are legacy, and new buckets
disable them by default.

---

## Common use cases

- Static website hosting (behind CloudFront, not public S3).
- Data lake — Athena queries Parquet directly in S3.
- Backups and archives with lifecycle to Glacier.
- **Terraform remote state** with a DynamoDB lock table (see
  [`../05-dynamodb-rds/`](../05-dynamodb-rds)) — the production answer to the
  local-state problem demonstrated in this session.
