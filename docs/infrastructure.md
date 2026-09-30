# Infrastructure: state, deployment, rollback, cost

Developer B's documentation deliverable for the Terraform/AWS delivery
side. Developer A's GitLab/Ansible operations and recovery docs live
separately (see `docs/recovery.md` for that half).

## Repositories involved

- `cloud-infrastructure` — all Terraform: five modules
  (`network`, `security`, `compute-foundation`, `billing-workloads`,
  `inventory-workloads`), one independent `shared/` state (ECR + CI IAM),
  and two thin `environments/staging` and `environments/production` roots.
- `api-gateway-app`, `billing-app`, `inventory-app` — application source
  and their own pipelines. **Do not run Terraform for an ordinary
  application release** — deploying a new image is entirely a
  `deploy-ecs-service.sh` operation (see Deployment below). Terraform only
  runs when the *infrastructure itself* changes.

## State management

Three independent Terraform states, one S3 bucket, separate keys (see
`docs/contracts.md`):

| Root | State key | Depends on |
|---|---|---|
| `shared/` | `code-keeper/shared/terraform.tfstate` | nothing |
| `environments/staging` | `code-keeper/staging/terraform.tfstate` | `shared/` (via `terraform_remote_state`, for ECR URLs) |
| `environments/production` | `code-keeper/production/terraform.tfstate` | `shared/` |

`shared/` must be applied **first**, once, before either environment —
both environment roots read its `ecr_repository_urls` output at plan time.
Locking is native S3 (`use_lockfile = true`, Terraform ≥ 1.10) — no
DynamoDB table to provision or pay for separately.

Every apply job in `ci-templates/terraform.yml` runs against a *saved*
plan file (`plan_staging`/`plan_production` produce `.tfplan` artifacts;
`apply_staging`/`apply_production` consume the exact same file) — the
plan a human or the pipeline reviewed is the plan that gets applied, never
an implicit re-plan.

## Deployment

Two entirely separate flows, deliberately not conflated:

**Infrastructure changes** (a `cloud-infrastructure` commit touching
`.tf` files): `init` → `validate` → `plan_staging`/`plan_production` →
`apply_staging` → `verify_staging` → `approve_production` (manual,
protected) → `apply_production` → `verify_production`. Both plans run in
the same pipeline, before staging is even applied — production's plan is
visible for review before anyone approves anything, not generated after
the fact.

**Application releases** (a commit to `api-gateway-app`, `billing-app`, or
`inventory-app`): build → test → scan → containerize (pushes one image,
tagged with the full `${CI_COMMIT_SHA}`, once) → `deploy_staging` (runs
`deploy-ecs-service.sh staging <service> <image> <container>`) →
`verify_staging` → `approve_production` → `deploy_production` (the *same*
image reference, promoted, never rebuilt) → `verify_production`. This
never touches Terraform state — `deploy-ecs-service.sh` only registers a
new task-definition revision and updates the service.

## Rollback

**Application rollback** — re-run `deploy-ecs-service.sh` with the
previous commit SHA's image reference:

```
deploy-ecs-service.sh <environment> <service> \
  <ecr-registry>/cloud-design/<service>:<previous-sha> <container-name>
```

If a deployment failed to stabilize, the script already printed the exact
`aws ecs update-service ...` command pointing at the *prior* task
definition revision — that's the fastest path back, no image rebuild
needed either way.

**Infrastructure rollback** — saved plan artifacts expire after 1 day, so
replaying an old plan generally isn't available by the time a problem
surfaces. Revert the offending commit in `cloud-infrastructure` and let
the pipeline produce a fresh plan and apply it through the normal gated
flow (including production's manual approval) — a deliberate choice, not
a gap: an unreviewed rollback `apply` is exactly the kind of change the
approval gate exists to catch too.

## Cost control

**Real finding, checked against actual current pricing, not guessed**:
running *both* environments continuously is meaningfully more expensive
than Cloud Design's original single-environment estimate, and plausibly
exceeds the project's stated $100/month budget if left running
unattended. `eu-central-1`, looked up rather than estimated from memory —
still worth re-verifying against the AWS Pricing Calculator before
committing a real budget number, since even the sources checked here
don't fully agree with each other on the EC2 figure:

| Resource | Per environment | Both, 24/7 |
|---|---:|---:|
| EC2 `m7i-flex.large` × 1 (ASG `desired_capacity`) | ~$70-84/month (sources disagree in this range) | ~$140-168/month |
| NAT Gateway × 1 | $37.96/month fixed (verified: $0.052/hr) + $0.052/GB processed | ~$76/month fixed, more with real traffic |
| EFS × 2, Secrets Manager × 3, CloudWatch, SNS, ECR | a few dollars/month | ~$10-15/month |

**Total if both environments run continuously: roughly $226-260/month
fixed, before any NAT data-processing charges** — over double the stated
$100/month budget. This is the single biggest cost lever in the whole
project, bigger than anything in the original Cloud Design estimate, and
worth surfacing before either environment is ever applied for real, not
discovered from a bill afterward.

Mitigations, in order of impact:
1. **Don't run both environments simultaneously except during active
   testing or the audit window itself.** Destroy one (or both) between
   work sessions — see Destroy below.
2. Staging doesn't need production's instance size or NAT redundancy;
   `environments/staging`'s `terraform.tfvars` can override `instance_type`
   down from `modules/environment`'s default if cost pressure is real.
3. Set a billing alert well under $100 (e.g. $50) so a forgotten running
   environment surfaces immediately, not at the end of the month.

## Destroy

`destroy_staging`/`destroy_production` in `ci-templates/terraform.yml`,
gated by both GitLab's manual-job mechanism and an explicit
`CONFIRM_DESTROY == "yes"` variable set at trigger time — never a normal
pipeline stage, never a stray click. Destroy environments before `shared/`
(the reverse of apply order) — `shared/`'s ECR repositories and IAM roles
are depended on by both environments' task definitions and CI role trust
policies.
