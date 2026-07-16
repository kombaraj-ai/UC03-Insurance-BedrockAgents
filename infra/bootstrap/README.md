# Bootstrap: Terraform Remote State Backend

This configuration exists to solve a chicken-and-egg problem: every other
Terraform configuration in this repo (`infra/live/<env>/`) stores its state in
an S3 bucket with a DynamoDB lock table, but Terraform can't create that
bucket/table for you from *within* a configuration that is itself trying to
use them as a backend.

## What this creates

- One S3 bucket (versioned, SSE-KMS via the AWS-managed `aws/s3` key, public
  access fully blocked, deny-non-TLS bucket policy) to hold `*.tfstate` files
  for every environment.
- One DynamoDB table (`PAY_PER_REQUEST`, SSE + PITR enabled) used as the
  state lock table for every environment.

## How it's applied

This directory intentionally has **no `backend` block** — it uses local
state (`terraform.tfstate` inside this folder). That local state file is the
one and only source of truth for the backend resources themselves.

```bash
cd infra/bootstrap
terraform init
terraform plan
terraform apply
```

Run this **once** per AWS account/region you deploy into. Note the two
outputs (`state_bucket_name`, `lock_table_name`) — you'll paste them into
`infra/live/<env>/backend.tf`.

## Operational rules

1. **Do not re-run `terraform apply` here as part of normal work.** This is a
   day-0, rarely-touched artifact. Both resources have
   `lifecycle { prevent_destroy = true }` as a safety net, but the discipline
   is still: leave this directory alone once it's applied.
2. **Do not delete `infra/bootstrap/terraform.tfstate`.** It is the only
   record Terraform has of these two resources. Back it up somewhere private
   (a team secrets vault, not committed to a public repo) — this repo's
   `.gitignore` excludes `*.tfstate*` for exactly this reason.
3. If you ever need to destroy the whole environment including the backend
   itself, you must empty and manually remove the `prevent_destroy` lifecycle
   blocks first, and only after every `infra/live/<env>` has already been
   destroyed (otherwise you orphan their state).
