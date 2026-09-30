# Shared delivery contract

This contract is shared by both developers. Changes must be reviewed before
dependent pipeline or infrastructure code is changed.

## Repositories and branches

| Purpose | GitLab project | Default protected branch |
|---|---|---|
| Inventory service | `inventory-app` | `main` |
| Billing service | `billing-app` | `main` |
| API gateway | `api-gateway-app` | `main` |
| Terraform infrastructure | `cloud-infrastructure` | `main` |

The GitLab group is `crud-master`. Changes reach `main` through merge requests.
Publication and deployment jobs run only for protected refs. The shared runner
tag is `docker-private`; untagged jobs are disabled.

## Environments and images

- Environment names are exactly `staging` and `production`.
- AWS region comes from the protected variable `AWS_REGION`.
- AWS account ID is discovered with `aws sts get-caller-identity`; it is not
  hard-coded.
- ECR repositories are `cloud-design/inventory-app`,
  `cloud-design/billing-app`, and `cloud-design/api-gateway-app`.
- Every pipeline builds one image tagged with the full `${CI_COMMIT_SHA}`.
- Production receives the same immutable tag/digest tested in staging.

## AWS naming

For an environment named `<environment>`:

- ECS cluster: `cloud-design-<environment>-cluster`
- Services: `inventory-app`, `billing-app`, and `api-gateway-app`
- Terraform state key: `code-keeper/<environment>/terraform.tfstate`
- Shared registry state key: `code-keeper/shared/terraform.tfstate`

Staging and production use the same Terraform modules but separate state,
networks, services, secrets, and application data.

## Application contract

| Application | Container name | Port | Health/smoke path |
|---|---:|---:|---|
| Inventory | `inventory-app` | `8080` | `/api/movies/` |
| Billing | `billing-app` | `8080` | consumer startup and queue processing |
| Gateway | `api-gateway-app` | `3000` | `/healthz` |

The shared deployment command has this interface:

```text
deploy-ecs-service.sh <environment> <service> <image-uri> <container-name>
```

It must register a new task-definition revision, replace only the selected
container image, update the ECS service, wait for stability, and return a
non-zero exit code on failure. It must not rebuild the image.

## Pipeline stages

Application repositories use:

```text
build -> test -> scan -> containerize -> deploy_staging -> verify_staging
      -> approve_production -> deploy_production -> verify_production
```

The infrastructure repository uses:

```text
init -> validate -> plan -> apply_staging -> verify_staging
     -> approve_production -> apply_production -> verify_production
```

Production approval is a protected manual job. Environment-specific deploy
jobs use GitLab `resource_group` locks to prevent concurrent changes.

## Required protected CI/CD variables

No value is stored in Git. The GitLab group or project settings provide:

- `AWS_ACCESS_KEY_ID` (masked, protected and preferably environment-scoped)
- `AWS_SECRET_ACCESS_KEY` (masked, protected and preferably environment-scoped)
- `AWS_REGION`
- `ECR_REGISTRY`
- `TF_STATE_BUCKET`
- `TF_IMAGE_TAG` (an existing immutable baseline image tag used by Terraform)
- `TF_LOCK_TABLE` when the selected backend requires it
- `STAGING_API_URL`
- `PRODUCTION_API_URL`
- `COGNITO_CLIENT_ID_STAGING`
- `COGNITO_CLIENT_ID_PRODUCTION`

GitLab administrative and runner bootstrap secrets are supplied through
Ansible Vault or runtime environment variables.

AWS OIDC federation is not used because this self-hosted GitLab instance is
reachable only through Tailscale over HTTP; AWS cannot securely discover it as
a public HTTPS OIDC issuer. The stored credentials must therefore belong to a
dedicated least-privilege CI identity and must never be committed to Git.
