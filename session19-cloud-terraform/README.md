# Session 19 — Cloud & Terraform in Action

**Name:** THRISHAL DOMA · **Enrollment Number:** 24BCS10097
**Environment:** Terraform v1.16.4 · AWS provider ~> 6.0 · **LocalStack 3.8** · aws-cli 1.44.87

An end-to-end AWS environment built, verified and torn down with Terraform.
Transcripts in [`logs/`](./logs), screenshots in [`screenshots/`](./screenshots).

> **No AWS account on this machine**, so the provider targets LocalStack — every
> command really executed against a real AWS API implementation. Set
> `use_localstack = false` and the identical configuration targets real AWS.
> Where the emulator diverges from AWS, I say so.

---

## Task — end-to-end cloud infrastructure with Terraform

Build a complete AWS environment with Terraform, demonstrating providers,
variables, resources, outputs, dependencies, state, and the plan/apply/destroy
lifecycle. The suggested architecture (VPC → Subnet → Security Group → EC2 → S3)
is implemented in full as 21 resources, applied, verified independently through
the AWS CLI, and destroyed.

### Architecture

```
                         Internet
                             │
                      ┌──────┴──────┐
                      │ Internet GW │
                      └──────┬──────┘
                             │  0.0.0.0/0
┌──────────────────── VPC 10.20.0.0/16 ─────────────────────┐
│                                                            │
│  ┌─── public rt ────────────────┬──────────────────────┐   │
│  │ public  10.20.1.0/24  AZ-a   │ public 10.20.2.0/24  │   │
│  │   └── EC2 t3.micro [web-sg]  │          AZ-b        │   │
│  └──────────────────────────────┴──────────────────────┘   │
│                      │ :8080 (SG reference, not a CIDR)    │
│  ┌─── private rt (no 0.0.0.0/0 route) ──────────────────┐   │
│  │ private 10.20.11.0/24 AZ-a │ private 10.20.12.0/24   │   │
│  │            [app-sg]        │          AZ-b           │   │
│  └────────────────────────────┴─────────────────────────┘   │
└────────────────────────────────────────────────────────────┘

        S3  session19-assets-<random>   (private · versioned · AES256)
```

**21 resources**, split by concern:

| File | Contents |
|---|---|
| [`infra/versions.tf`](./infra/versions.tf) | `required_version`, `required_providers` |
| [`infra/provider.tf`](./infra/provider.tf) | AWS provider, LocalStack endpoints, `default_tags` |
| [`infra/variables.tf`](./infra/variables.tf) | typed inputs with validation |
| [`infra/network.tf`](./infra/network.tf) | VPC, 4 subnets, IGW, route tables, associations |
| [`infra/security.tf`](./infra/security.tf) | web + app security groups |
| [`infra/compute.tf`](./infra/compute.tf) | AMI data source, EC2 instance |
| [`infra/storage.tf`](./infra/storage.tf) | S3 bucket, hardening, object |
| [`infra/outputs.tf`](./infra/outputs.tf) | 9 outputs |

---

## The eight concepts the task asks for

### 1. Providers

```hcl
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.project, Environment = var.environment, ManagedBy = "Terraform" }
  }
}
```

`default_tags` applies to **every** resource the provider creates — the cheapest
way to make cost allocation and ownership work, because it cannot be forgotten
on a new resource.

### 2. Variables — typed, defaulted and **validated**

```hcl
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}
```

A typo fails in milliseconds at plan time with a readable message, rather than
part-way through an apply with a cryptic AWS error.

### 3. Resources — derived, not copy-pasted

```hcl
resource "aws_subnet" "public" {
  for_each   = toset(var.availability_zones)
  cidr_block = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.key) + 1)
  availability_zone = "${var.aws_region}${each.key}"
}
```

`for_each` plus `cidrsubnet()` means changing `vpc_cidr` re-derives all four
subnets. The course reference hardcodes a single subnet CIDR; with four subnets
that becomes four places to edit and get wrong.

Verified:

```
|      AZ      |      CIDR       | Public  |
|  ap-south-1a |  10.20.1.0/24   |  True   |
|  ap-south-1a |  10.20.11.0/24  |  False  |
|  ap-south-1b |  10.20.2.0/24   |  True   |
|  ap-south-1b |  10.20.12.0/24  |  False  |
```

### 4. Outputs

```
vpc_id              = "vpc-d2e7a016"
vpc_cidr            = "10.20.0.0/16"
instance_id         = "i-0c53b54c43ffacc9e"
instance_private_ip = "10.20.1.4"
bucket_name         = "session19-assets-04a1d8af"
public_subnet_ids   = { "a" = "subnet-033744fa", "b" = "subnet-c5d85eae" }
```

### 5. Dependencies — implicit and explicit

**Implicit** is the normal case: Terraform reads the references and builds the graph.

```
$ terraform graph | grep 'aws_instance.web" ->'
  "aws_instance.web" -> "data.aws_ami.amazon_linux";
  "aws_instance.web" -> "aws_security_group.web";
  "aws_instance.web" -> "aws_subnet.public";
```

**Explicit** is for ordering with no data flowing between resources:

```hcl
resource "aws_s3_object" "readme" {
  depends_on = [aws_instance.web]   # nothing here references the instance
}
```

`depends_on` is a last resort — overusing it serialises a plan that could have
run in parallel.

### 6. `terraform plan` / `apply`

```
Plan: 21 to add, 0 to change, 0 to destroy.
...
Apply complete! Resources: 21 added, 0 changed, 0 destroyed.
```

### 7. State

```
$ terraform state list | wc -l
22        # 21 resources + 1 data source
```

Local state is used deliberately so the problem is visible: it is a single file
on one laptop with no locking. Production uses an **S3 backend with a DynamoDB
lock table** (see [Session 18's DynamoDB notes](../session18-terraform-iac/aws-services/05-dynamodb-rds)).

### 8. `terraform destroy` — reverse order, derived automatically

```
 1. aws_s3_bucket_server_side_encryption_configuration.assets
 3. aws_s3_object.readme
10. aws_subnet.private["a"]
16. aws_internet_gateway.main
17. aws_instance.web
19. aws_subnet.public["a"]
21. aws_vpc.main                     <-- last
```

`aws_vpc.main` is destroyed **last** because everything else lives inside it —
you cannot delete a VPC that still contains subnets. Nobody wrote that ordering;
Terraform walked the same dependency graph backwards.

---

## Independent verification

Terraform reporting success is not proof. Every resource was re-read through the
**AWS CLI**, which issues properly signed requests:

```
$ aws --endpoint-url=http://localhost:4566 ec2 describe-instances
|          Id          | PrivateIP  |  State   |   Type     |
|  i-0c53b54c43ffacc9e |  10.20.1.4 |  running |  t3.micro  |

$ aws ... ec2 describe-security-groups --filters Name=group-name,Values=session19-app-sg \
      --query 'SecurityGroups[0].IpPermissions[0].UserIdGroupPairs[].GroupId'
sg-e771915b90ebd378b
$ terraform output -raw web_security_group_id
sg-e771915b90ebd378b   <- matches
```

That last pair is the important one: the app tier's ingress rule references the
**web security group by ID**, not a CIDR. The chain keeps working when instances
are replaced and their IPs change.

After destroy, only LocalStack's own default VPC remains:

```
$ aws ... ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --output text
172.31.0.0/16
$ aws ... s3 ls
(no buckets)
resources left in state: 0
```

> **A verification gotcha worth recording.** Unauthenticated `curl` against
> LocalStack only ever returned the *default* VPC — EC2 actions require
> SigV4-signed requests, so an unsigned call silently answers from a different
> context. It looks like "Terraform didn't create anything". S3 path-style GETs
> work unsigned, which is why the bucket check succeeded while the VPC check
> misled. Use the real CLI to verify.

📄 [`logs/01-end-to-end-infra.txt`](./logs/01-end-to-end-infra.txt) · 📸 [`01-end-to-end-infra.png`](./screenshots/01-end-to-end-infra.png)

---

## Security decisions, and why

| Decision | Reason |
|---|---|
| No port 22 rule | SSH open to `0.0.0.0/0` is the most common AWS misconfiguration. Use SSM Session Manager |
| `app-sg` references `web-sg`, not a CIDR | survives instance replacement; expresses the tier boundary |
| Private route table has **no** `0.0.0.0/0` | those subnets genuinely cannot reach the internet |
| `http_tokens = "required"` | IMDSv2 only — mitigates SSRF stealing instance credentials |
| `encrypted = true` on the root volume | EBS encryption cannot be added later without a snapshot/restore |
| S3 public-access block + versioning + AES256 | public buckets are the classic cloud breach |
| AMI via `data` source | AMI IDs are region-specific; a literal breaks on region change |

**NAT Gateway deliberately omitted.** Private subnets therefore have no outbound
internet. That is a real limitation, not an oversight: NAT is billed hourly *and*
per-GB and is the line item that most often surprises people. Production would
add one per AZ, or VPC endpoints for S3/ECR to bypass NAT entirely.

---

## Reproducing

```bash
docker run -d --name localstack -p 4566:4566 \
  -e SERVICES=s3,iam,ec2,dynamodb,sts localstack/localstack:3.8

cd infra
terraform init && terraform validate
terraform apply -auto-approve
terraform output

export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1
aws --endpoint-url=http://localhost:4566 ec2 describe-instances --output table

terraform destroy -auto-approve
```
