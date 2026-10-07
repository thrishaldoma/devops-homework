# IAM — Identity & Access Management (Governance)

**Session 18, Task 2.1**

IAM answers one question for every single AWS API call: **"is this principal
allowed to perform this action on this resource?"** It is global (not regional),
free, and it is the control plane for everything else.

---

## The four building blocks

| Object | What it is | Has credentials? |
|---|---|---|
| **User** | a single long-lived identity (a person or a legacy service) | yes — password and/or access keys |
| **Group** | a bucket of users; policies attach here | no |
| **Role** | a set of permissions that is **assumed temporarily** | no — credentials are issued on assume, and expire |
| **Policy** | the JSON document that grants or denies | n/a |

### Why roles matter more than users

A user's access key is a static secret: it lives in a config file, gets copied
into a `.env`, and leaks. A **role** issues short-lived credentials through STS
that expire in minutes.

In practice:
- **EC2 instance** → attach an *instance profile*, the SDK picks credentials up automatically.
- **Pod in EKS** → **IRSA**, which maps a Kubernetes ServiceAccount to an IAM role.
- **GitHub Actions** → **OIDC federation**: the workflow trades its signed token for temporary AWS credentials, so no AWS key is ever stored as a GitHub secret.

That last one is exactly the problem Session 17 solved for the container registry
by using `GITHUB_TOKEN` instead of a stored credential — the same principle.

---

## Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ReadOneBucket",
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::yatri-session18-demo",
      "arn:aws:s3:::yatri-session18-demo/*"
    ],
    "Condition": { "Bool": { "aws:SecureTransport": "true" } }
  }]
}
```

Note the two ARNs: bucket-level actions (`ListBucket`) target the bucket;
object-level actions (`GetObject`) target `bucket/*`. Getting this wrong is the
most common reason an S3 policy "doesn't work".

**Policy types:** *identity-based* (attached to a user/group/role),
*resource-based* (attached to the resource, e.g. an S3 bucket policy — these can
grant cross-account access), *SCPs* (Organization-wide ceilings), and
*permission boundaries* (a cap on what a role can ever be granted).

### How a request is actually evaluated

```
Explicit DENY anywhere?        ──► DENY   (always wins, nothing overrides it)
        │ no
Explicit ALLOW in some policy? ──► ALLOW
        │ no
                               ──► DENY   (implicit: default is deny)
```

Two consequences worth remembering: permissions are **deny by default**, and a
single explicit `Deny` in an SCP or boundary cannot be overridden by any `Allow`.

---

## Least privilege, practically

"Least privilege" is easy to say and hard to start from. The workable method:

1. Start with an AWS managed policy to get moving.
2. Run the workload, then read **CloudTrail** / IAM Access Analyzer for the actions actually used.
3. Replace the managed policy with a generated least-privilege one.
4. Re-check periodically — unused permissions accumulate.

**Avoid `"Action": "*"` with `"Resource": "*"`.** That is
`AdministratorAccess` wearing a disguise.

---

## Best practices

| Practice | Why |
|---|---|
| Never use the **root** account; lock it with MFA and no access keys | root cannot be restricted by IAM policy |
| Prefer **roles** over users | no long-lived secrets to leak |
| **MFA** on every human | password compromise alone is then not enough |
| Attach policies to **groups**, not users | permissions stay reviewable as people move teams |
| **Rotate** access keys; delete unused ones | IAM's credential report lists them |
| Use **conditions** (`aws:SourceIp`, `aws:SecureTransport`, `aws:MultiFactorAuthPresent`) | narrows a grant without narrowing the action list |
| Separate **accounts** per environment | the hardest blast-radius boundary AWS offers |

## Common use cases

- An EC2 instance reading from S3 → instance profile, no keys on disk.
- A CI pipeline deploying → OIDC role with a trust policy scoped to one repo and branch.
- Cross-account access → a role in account B with a trust policy naming account A.
- Break-glass admin → a role requiring MFA, with CloudTrail alerting on assumption.

> **Seen in this session:** Terraform's provider is configured with
> `skip_credentials_validation` against LocalStack precisely because there is no
> real IAM behind it. On real AWS that call is what proves who you are before any
> resource is touched.
