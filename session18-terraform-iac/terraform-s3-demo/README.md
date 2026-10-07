# terraform-s3-demo

**Session 18, Task 1.** An S3 bucket provisioned with Terraform, taken through the
complete lifecycle the assignment lists.

```
terraform-s3-demo/
├── terraform.tf       # required_version + required_providers
├── provider.tf        # AWS provider (LocalStack endpoints, default_tags)
├── variables.tf       # typed inputs with validation
├── main.tf            # the bucket + 3 hardening resources
├── outputs.tf         # name, ARN, region, versioning status
├── terraform.tfvars   # values for this environment
└── README.md          # this file
```

> The assignment names the provider file `provider.tf`; the provider block lives
> there. `terraform.tf` holds only the `terraform {}` settings block, which keeps
> version pinning separate from provider configuration.

---

## No AWS account — targeting LocalStack

There are no AWS credentials on this machine, so the provider points at
**LocalStack**, an AWS API emulator in Docker on `:4566`. Every command below
really executed against a real API implementation; only the cloud behind it is
simulated.

```hcl
use_localstack = true    # terraform.tfvars
```

Set it to `false` and the endpoint overrides disappear — the same configuration
targets real AWS.

```bash
docker run -d --name localstack -p 4566:4566 \
  -e SERVICES=s3,iam,ec2,dynamodb,sts localstack/localstack:3.8
```

---

## What it creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.demo` | the bucket, `force_destroy = true` so `destroy` works on a non-empty bucket |
| `aws_s3_bucket_public_access_block.demo` | blocks all four public-access vectors |
| `aws_s3_bucket_versioning.demo` | makes an accidental delete or overwrite recoverable |
| `aws_s3_bucket_server_side_encryption_configuration.demo` | AES256 at rest |

The assignment asks only for a bucket. The other three are added because a bare
`aws_s3_bucket` is exactly the configuration behind most public-bucket breaches —
and they cost nothing.

---

## The workflow

```bash
terraform init        # download the AWS provider
terraform fmt         # canonical formatting
terraform validate    # syntax + type checking
terraform plan        # what WOULD change
terraform apply       # make it so
terraform show        # full state
terraform output      # just the outputs
terraform destroy     # tear it down
```

Captured results:

```
$ terraform validate
Success! The configuration is valid.

$ terraform plan
Plan: 4 to add, 0 to change, 0 to destroy.

$ terraform apply -auto-approve
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
bucket_arn        = "arn:aws:s3:::yatri-session18-demo"
bucket_name       = "yatri-session18-demo"
bucket_region     = "ap-south-1"
versioning_status = "Enabled"

$ terraform destroy -auto-approve
Destroy complete! Resources: 4 destroyed.
```

Verified independently through the S3 API rather than Terraform's own state:

```
$ curl -o /dev/null -w '%{http_code}' http://localhost:4566/yatri-session18-demo
200                                                   # 404 after destroy
$ curl 'http://localhost:4566/yatri-session18-demo?versioning'
<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>
```

Full transcript: [`../logs/01-terraform-workflow.txt`](../logs/01-terraform-workflow.txt)

---

## Three things this demonstrates

**Idempotency** — `terraform plan` after `apply` reports
`No changes. Your infrastructure matches the configuration.` The config describes
a *desired state*, so re-running is a no-op rather than creating a second bucket.

**Drift detection** — deleting the bucket out-of-band through the S3 API, then
re-planning:

```
# aws_s3_bucket.demo has been deleted
# aws_s3_bucket.demo will be created
```

Terraform refreshed state, saw reality had diverged, and planned to restore it.
That refresh is why you never click in the console on a Terraform-managed resource.

**Input validation** — a bad bucket name fails at plan time in milliseconds:

```hcl
validation {
  condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
  error_message = "bucket_name must be 3-63 characters, lowercase alphanumeric or hyphens..."
}
```

---

## Notes on the course reference

- **`outputs.tf` used `type = string` inside each `output` block.** Terraform
  rejects that — an output has no `type` argument and infers it from `value`.
  Corrected here, with the reason noted inline.
- **A LocalStack fidelity gap:** the first `apply` left tags empty
  (`terraform show` reported `tags = {}`), so the next plan wanted to correct
  them. That is an emulator limitation, not Terraform drift — but it is
  indistinguishable from real drift at the CLI, which is worth knowing when
  learning against an emulator.

## State

State is local and deliberately so, to make the problem visible: one file, one
laptop, no locking. `.gitignore` keeps `*.tfstate` out of the repository.
Production uses a remote **S3 backend with a DynamoDB lock table** — see
[`../aws-services/05-dynamodb-rds/`](../aws-services/05-dynamodb-rds).
