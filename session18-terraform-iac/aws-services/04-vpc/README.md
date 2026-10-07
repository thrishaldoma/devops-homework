# VPC — Virtual Private Cloud (Networking)

**Session 18, Task 2.4** — the networking built in
[Session 19](../../../session19-cloud-terraform).

A VPC is your own isolated network inside AWS. Nothing in it is reachable from
the internet until you explicitly build a path.

---

## CIDR

A CIDR block is `address/prefix`; the prefix is how many bits are fixed.

| CIDR | Addresses | Typical use |
|---|---|---|
| `10.0.0.0/16` | 65,536 | a whole VPC |
| `10.0.1.0/24` | 256 | one subnet |
| `10.0.1.0/28` | 16 | a tiny subnet |

**AWS reserves 5 addresses in every subnet** (network, VPC router, DNS, future
use, broadcast), so a `/24` gives you **251** usable, not 256.

Choose non-overlapping private ranges (RFC 1918: `10/8`, `172.16/12`,
`192.168/16`). Overlapping CIDRs make VPC peering impossible later — a decision
that is painful to reverse.

---

## Subnets

A subnet is a slice of the VPC CIDR **pinned to one Availability Zone**. That
makes subnets your unit of fault isolation: spread across at least two AZs.

```
VPC 10.0.0.0/16
├── 10.0.1.0/24  public   AZ-a   ──► route 0.0.0.0/0 to IGW
├── 10.0.2.0/24  public   AZ-b   ──► route 0.0.0.0/0 to IGW
├── 10.0.11.0/24 private  AZ-a   ──► route 0.0.0.0/0 to NAT
└── 10.0.12.0/24 private  AZ-b   ──► route 0.0.0.0/0 to NAT
```

**The only thing that makes a subnet "public" is its route table.** There is no
`public = true` flag — a public subnet is one whose route table sends `0.0.0.0/0`
to an Internet Gateway.

---

## Route tables

| Destination | Target | Meaning |
|---|---|---|
| `10.0.0.0/16` | `local` | intra-VPC traffic (always present, cannot be removed) |
| `0.0.0.0/0` | `igw-…` | → public subnet |
| `0.0.0.0/0` | `nat-…` | → private subnet |

Most specific prefix wins, so a `/32` route overrides a `/0`.

## Internet Gateway vs NAT Gateway

| | Internet Gateway | NAT Gateway |
|---|---|---|
| Direction | **both ways** | **outbound only** |
| Attached to | the VPC (one per VPC) | a **public** subnet |
| Cost | free | **hourly + per-GB** |
| Needed for | public subnets | private subnets reaching the internet |

The NAT Gateway is the line item that surprises people. It is billed per hour
*and* per GB processed; a chatty private subnet pulling container images through
NAT can cost more than the instances. Mitigations: **VPC endpoints** for S3 and
ECR (traffic never leaves the AWS network and skips NAT entirely), and one NAT
per AZ only when you genuinely need AZ-level resilience.

---

## Security Groups vs Network ACLs

| | Security Group | Network ACL |
|---|---|---|
| Attached to | an ENI / instance | a **subnet** |
| State | **stateful** | **stateless** |
| Rules | allow only | allow **and deny** |
| Evaluation | all rules together | numbered, first match wins |

**Stateless is the one that catches people.** With a NACL you must write the
return-traffic rule yourself, including the ephemeral port range
(`1024–65535`) — allowing inbound 443 without the matching outbound ephemeral
rule produces a connection that opens and then hangs.

In practice: use **security groups** for nearly everything; reach for NACLs only
to blanket-deny something at the subnet edge (e.g. block a hostile CIDR).

---

## Public vs private subnet — what goes where

```
                    Internet
                        │
                   [ IGW ]
                        │
  ┌─────────── public subnet ────────────┐
  │  ALB · NAT Gateway · bastion         │
  └──────────────┬───────────────────────┘
                 │  (NAT: outbound only)
  ┌─────────── private subnet ───────────┐
  │  app servers · EKS nodes · RDS       │
  └──────────────────────────────────────┘
```

Rule of thumb: **only load balancers and NAT belong in public subnets.** If a
database has a public IP, that is a finding.

## Other pieces worth naming

- **VPC Endpoints** — private connectivity to AWS services. *Gateway* endpoints (S3, DynamoDB) are free; *Interface* endpoints are hourly.
- **VPC Peering** — 1:1, non-transitive, requires non-overlapping CIDRs.
- **Transit Gateway** — hub-and-spoke for many VPCs; transitive.
- **Flow Logs** — connection-level logging; the first thing to enable when debugging "it can't connect".

## Debugging "I can't reach it"

Check in this order — the failure is almost always one of these, in this order of likelihood:

1. **Security group** inbound rule missing
2. **Route table** has no path (no IGW/NAT route)
3. Instance is in a **private subnet** with no NAT
4. **NACL** blocking return traffic (the stateless trap)
5. No **public IP** assigned
6. The application isn't actually listening — `ss -tlnp`

> Session 14's Kubernetes equivalent of step 6 was the `targetPort` mismatch:
> endpoints existed, but nothing was listening on the port. Same debugging shape,
> different layer.
