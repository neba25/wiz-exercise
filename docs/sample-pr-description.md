# PR: Bump Mongo VM instance type for backup headroom

## What changed
- `terraform/mongo_vm.tf`: `mongo_instance_type` default bumped from `t3.medium` to `t3.large` to give the nightly `mongodump` job more headroom during backup windows.

## Why
Backup duration has been creeping up as demo data grows; a larger instance type avoids CPU contention with the live app during the 03:00 UTC backup window.

## How this was tested
- `terraform fmt -check` / `terraform validate` pass locally.
- Reviewed `terraform plan` output below — only the Mongo VM's instance type changes; no other resources are affected.

## Demo notes for the panel
This PR is intentionally small so the `iac-deploy.yml` pipeline's checks are
easy to follow live:
1. Opening this PR triggers `validate-and-scan` (fmt, validate, Checkov, tfsec).
2. Because this is a PR, the `plan` job also runs and posts the Terraform plan
   output as a check — no infrastructure changes yet.
3. Merging to `main` triggers the `apply` job, which pauses on the
   `production` GitHub Environment for manual approval before actually
   resizing the instance.

## Checklist
- [x] Terraform fmt/validate clean
- [x] No secrets introduced
- [x] Reviewed Checkov/tfsec findings (pre-existing intentional-weakness
      findings acknowledged, no new findings introduced by this change)
