# EC2 — Elastic Compute Cloud (Compute)

**Session 18, Task 2.2**

EC2 is a virtual machine you rent by the second. Everything else about it — the
disk, the firewall, the key — is a separate object you attach.

---

## AMI — Amazon Machine Image

The template an instance boots from: OS, pre-installed software, configuration.
AMIs are **region-specific** (the same logical image has a different ID per
region), which is why Terraform usually looks one up rather than hardcoding it:

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

Baking a **golden AMI** (with Packer) makes boots fast and reproducible —
the same idea as a container image, one layer down the stack.

---

## Instance types

Named `family + generation + size`, e.g. **`t3.medium`**.

| Family | Optimised for | Example |
|---|---|---|
| **T** | burstable, cheap baseline + CPU credits | dev boxes, low-traffic apps |
| **M** | balanced | general web/app servers |
| **C** | compute | batch processing, CI runners |
| **R / X** | memory | caches, in-memory databases |
| **I / D** | local NVMe storage | high-IOPS databases |
| **G / P / Inf** | GPU / accelerators | ML training and inference |

**The T-family trap:** `t3`/`t4g` instances earn CPU credits at a baseline rate.
A sustained-load workload exhausts its credits and is then throttled to baseline
— the instance looks "slow" with no obvious cause. Use M or C for steady load.

`t4g`/`m7g` are **Graviton** (arm64) — noticeably cheaper, but your container
images must be arm64. This repo's cluster is arm64 for exactly that reason, and
Session 14 hit the consequence: an image with no arm64 manifest fails to pull.

---

## Key pairs

An SSH **public** key AWS injects into the instance at first boot; you keep the
private half. AWS never stores the private key, so **losing it means losing SSH
access** to that instance.

Better than key pairs in practice: **SSM Session Manager**, which gives a shell
through the AWS API with no open port 22, no key to lose, and full CloudTrail
audit of every session.

---

## Security Groups

A **stateful** virtual firewall attached to an ENI.

- Rules are **allow-only** — you cannot write a deny rule.
- **Stateful**: allow inbound 443 and the response goes out automatically; no outbound rule needed.
- Default: **deny all inbound, allow all outbound**.
- A source can be a CIDR **or another security group** — the idiomatic pattern:

```
ALB-SG      inbound  443 from 0.0.0.0/0
App-SG      inbound 8080 from ALB-SG        <-- not a CIDR
DB-SG       inbound 5432 from App-SG
```

That chain means the database is reachable only by the app tier, and it keeps
working when instances are replaced and IPs change.

`0.0.0.0/0` on port 22 is the single most common AWS misconfiguration.

---

## EBS — Elastic Block Store

Network-attached block storage; a virtual disk.

| Type | Use |
|---|---|
| **gp3** | default. Baseline 3000 IOPS, throughput configured independently of size |
| **io2 Block Express** | databases needing guaranteed high IOPS |
| **st1 / sc1** | throughput-optimised / cold HDD, big sequential data |

Key properties: EBS lives in **one AZ**, persists independently of the instance,
and supports point-in-time **snapshots** (incremental, stored in S3).

> **gp2 vs gp3:** on gp2, IOPS scaled with volume *size*, so people over-provisioned
> disk to buy performance. gp3 decouples them and is cheaper. Migrate.

**Instance store** is different: physical NVMe on the host, very fast, and
**erased when the instance stops**. Cache only.

---

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| Reachable from | inside the VPC | internet | internet |
| Survives stop/start | yes | **no** (re-assigned) | yes |
| Cost | free | free while attached | charged when *not* attached |

An instance in a **private subnet** has no public IP and reaches the internet
through a **NAT Gateway** — outbound only. That is where application servers and
databases belong. See [`../04-vpc/`](../04-vpc).

---

## Instance lifecycle

```
pending ──► running ──┬──► stopping ──► stopped ──► (start again)
                      ├──► rebooting ──► running
                      └──► shutting-down ──► terminated   (permanent)
```

- **Stop**: EBS persists, public IP is lost, no compute charge (EBS still billed).
- **Terminate**: gone. Root volume is deleted unless `delete_on_termination = false`.
- **Hibernate**: RAM is written to EBS and restored on start.

## Purchasing options

| Option | Saving | Trade-off |
|---|---|---|
| On-Demand | — | most flexible |
| **Spot** | up to 90% | can be reclaimed with a 2-minute warning |
| Reserved / Savings Plans | up to 72% | 1–3 year commitment |
| Dedicated Host | — | licensing/compliance |

Spot plus an Auto Scaling Group is the standard way to run fault-tolerant batch
and CI workloads cheaply.

## Common use cases

- Web/app servers behind an ALB in an Auto Scaling Group.
- Self-managed Kubernetes nodes (what EKS node groups are underneath).
- Batch and CI runners on Spot.
- Lift-and-shift of workloads that are not yet containerised.
