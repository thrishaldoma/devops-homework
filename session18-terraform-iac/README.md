# Session 18 — Terraform & Infrastructure as Code

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64) · **Terraform v1.16.4** · AWS provider ~> 6.0 · **LocalStack 3.8**

Transcripts in [`logs/`](./logs), screenshots in [`screenshots/`](./screenshots).

### Environment note — no AWS account

There are no AWS credentials on this machine. Rather than stop at
`terraform plan`, the provider targets **LocalStack**, an AWS API emulator
running in Docker on `:4566`. Every command the assignment lists —
`init`, `fmt`, `validate`, `plan`, `apply`, `show`, `output`, `destroy` —
**really executed against a real API implementation**; only the cloud behind it
is simulated. Resources were created, verified through the raw S3 API, and
destroyed.

Switching to real AWS is one variable:

```hcl
use_localstack = false   # drops the endpoint overrides; same config targets AWS
```

LocalStack is not a perfect emulator, and where it diverged I have said so
(see the tagging note under *Drift detection*).

---

## Task 1 — `terraform-s3-demo`

```
terraform-s3-demo/
├── terraform.tf       # required_version + required_providers
├── provider.tf        # AWS provider, LocalStack endpoints, default_tags
├── variables.tf       # typed inputs with validation
├── main.tf            # the bucket + 3 hardening resources
├── outputs.tf         # bucket name, ARN, region, versioning status
├── terraform.tfvars   # values for this environment
└── README.md
```

The assignment asks for a bucket. I added three resources around it, because a
bare `aws_s3_bucket` is exactly the configuration that causes real breaches:

| Resource | Why |
|---|---|
| `aws_s3_bucket_public_access_block` | blocks all four public-access vectors |
| `aws_s3_bucket_versioning` | makes an accidental delete or overwrite recoverable |
| `aws_s3_bucket_server_side_encryption_configuration` | AES256 at rest, free |

### The full workflow

**1–3 · init, fmt, validate**

```
$ terraform init
Terraform has been successfully initialized!

$ terraform fmt -check -diff
exit: 0

$ terraform validate
Success! The configuration is valid.
```

**4 · plan** — what *would* change, before anything does

```
Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_arn        = (known after apply)
  + bucket_name       = "yatri-session18-demo"
  + bucket_region     = "ap-south-1"
  + versioning_status = "Enabled"
```

**5 · apply**

```
aws_s3_bucket_public_access_block.demo: Creation complete after 0s
aws_s3_bucket_server_side_encryption_configuration.demo: Creation complete after 0s
aws_s3_bucket_versioning.demo: Creation complete after 1s

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
bucket_arn = "arn:aws:s3:::yatri-session18-demo"
bucket_name = "yatri-session18-demo"
versioning_status = "Enabled"
```

**Independent proof** — querying the S3 API directly, not Terraform's own state:

```
$ curl -o /dev/null -w '%{http_code}' http://localhost:4566/yatri-session18-demo
200
$ curl 'http://localhost:4566/yatri-session18-demo?versioning'
<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>
```

**6–7 · show, output**

```
$ terraform output -json | python3 -m json.tool
{ "bucket_arn": { "sensitive": false, "type": "string",
                  "value": "arn:aws:s3:::yatri-session18-demo" }, ... }
```

`output -json` is the pipeline-facing form — how a CI job hands a bucket ARN to
the next stage.

**8 · destroy**

```
Destroy complete! Resources: 4 destroyed.

$ curl -o /dev/null -w '%{http_code}' http://localhost:4566/yatri-session18-demo
404
resources left in state: 0
```

📄 [`logs/01-terraform-workflow.txt`](./logs/01-terraform-workflow.txt) · 📸 [`01-terraform-workflow.png`](./screenshots/01-terraform-workflow.png)

---

## What the workflow actually demonstrates

### Idempotency

```
$ terraform plan
No changes. Your infrastructure matches the configuration.
```

This is the declarative property. The config describes a **desired state**, so
re-running `apply` is a no-op rather than creating a second bucket. A shell
script of `aws s3 mb` commands does not behave this way.

### Drift detection

Deleting the bucket behind Terraform's back, through the S3 API:

```
$ curl -X DELETE http://localhost:4566/yatri-session18-demo      -> 204
$ curl           http://localhost:4566/yatri-session18-demo      -> 404

$ terraform plan
  # aws_s3_bucket.demo has been deleted
  # aws_s3_bucket.demo will be created
  # aws_s3_bucket_public_access_block.demo will be created
  ...
```

Terraform refreshed state, noticed reality had diverged, and planned to restore
it. **That refresh is why you never click in the console on a Terraform-managed
resource** — the next `apply` silently reverts you.

> **A LocalStack fidelity gap, reported honestly.** The first `apply` left tags
> empty (`terraform show` reported `tags = {}`) even though the config sets them,
> so the following plan wanted to "fix" them. That is an emulator limitation, not
> Terraform drift — but it is indistinguishable from real drift at the CLI, which
> is worth knowing when learning against an emulator.

### State

```
$ terraform state list
aws_s3_bucket.demo
aws_s3_bucket_public_access_block.demo
aws_s3_bucket_server_side_encryption_configuration.demo
aws_s3_bucket_versioning.demo
```

State is the mapping between configuration and real resource IDs. Delete it and
Terraform forgets the resources exist — it will try to **create** them again and
fail on name conflicts. Hence the production rules:

- **remote backend** (S3) so the team shares one state;
- **DynamoDB lock table** so two engineers cannot apply simultaneously;
- **never in Git** — state contains resource attributes and can contain secrets.

This project uses local state deliberately, so the problem is visible.
[`.gitignore`](./terraform-s3-demo/.gitignore) keeps `*.tfstate` out of the repo.

### Input validation catches mistakes before the API does

```hcl
validation {
  condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
  error_message = "bucket_name must be 3-63 characters, lowercase alphanumeric or hyphens..."
}
```

A bad bucket name fails in milliseconds at plan time with a readable message,
instead of half-way through an apply with an opaque AWS error.

### A defect in the course reference

The course's `outputs.tf` declares `type = string` inside each `output` block.
Terraform rejects that — an output has no `type` argument; it infers the type
from `value`. The corrected file notes this inline.

---

## Task 2 — AWS services

Five write-ups, each covering the assignment's required points plus the failure
modes that matter in practice:

| Service | Document | Covers |
|---|---|---|
| **IAM** | [`aws-services/01-iam/`](./aws-services/01-iam) | users · groups · roles · policies · evaluation order · least privilege · OIDC federation |
| **EC2** | [`aws-services/02-ec2/`](./aws-services/02-ec2) | AMI · instance families · key pairs · security groups · EBS · public vs private IP · lifecycle |
| **S3** | [`aws-services/03-s3/`](./aws-services/03-s3) | buckets · objects · storage classes · versioning · lifecycle · encryption · bucket policies |
| **VPC** | [`aws-services/04-vpc/`](./aws-services/04-vpc) | CIDR · subnets · route tables · IGW vs NAT · SG vs NACL · public/private |
| **DynamoDB & RDS** | [`aws-services/05-dynamodb-rds/`](./aws-services/05-dynamodb-rds) | partition/sort keys · query vs scan · engines · Multi-AZ vs read replicas · backups |

Each one is tied back to something demonstrated elsewhere in this repo — IAM
roles to Session 17's use of `GITHUB_TOKEN` instead of a stored secret, the RDS
credentials section to Session 12's Secret handling, and the VPC debugging
checklist to Session 14's `targetPort` mismatch.

---

## Reproducing

```bash
docker run -d --name localstack -p 4566:4566 \
  -e SERVICES=s3,iam,ec2,dynamodb,sts localstack/localstack:3.8

cd terraform-s3-demo
terraform init && terraform validate
terraform apply -auto-approve
curl -s 'http://localhost:4566/yatri-session18-demo?versioning'
terraform destroy -auto-approve
```
