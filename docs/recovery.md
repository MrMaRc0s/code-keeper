# Recovery and rollback runbook

Use this runbook when GitLab, the Runner, an application deployment or the
Terraform infrastructure fails. Never copy credentials into a command,
ticket, log or repository.

## GitLab service

Check the container and its health before changing anything:

```bash
docker ps -a --filter name=code-keeper-gitlab
docker logs --tail 100 code-keeper-gitlab
curl --fail http://<gitlab-host>:8929/-/health
```

GitLab state is persisted under `/srv/code-keeper/gitlab/config`, `data` and
`logs`; recreating the container does not remove these directories. Reapply
the idempotent playbook to restore the declared configuration:

```bash
cd ansible
ansible-playbook playbooks/deploy-gitlab.yml \
  --ask-vault-pass --extra-vars '@vault.yml'
```

Then rerun `bootstrap-gitlab.yml` to restore missing projects, protected main
branches and the CI job-token allowlist. This playbook does not overwrite
existing repositories.

## GitLab Runner

```bash
docker ps -a --filter name=code-keeper-runner
docker logs --tail 100 code-keeper-runner
docker exec code-keeper-runner gitlab-runner verify
```

If the Runner authentication token was revoked, create a replacement protected
group Runner token, update `vault_gitlab_runner_token` with `ansible-vault
edit vault.yml`, remove only the obsolete Runner configuration, and rerun:

```bash
ansible-playbook playbooks/deploy-runner.yml \
  --ask-vault-pass --extra-vars '@vault.yml'
```

## Application rollback

Find the previous known-good commit tag in ECR, then deploy that immutable
image. The script registers a new task-definition revision and waits until ECS
reports a completed rollout:

```bash
scripts/deploy-ecs-service.sh <staging|production> <service> \
  <ecr-registry>/cloud-design/<service>:<previous-commit-sha> <container-name>
```

The same rollback can be performed by reverting the application commit and
using its normal pipeline. Never rebuild an old source revision under a new
tag—the already scanned ECR image is the release artifact.

## Infrastructure rollback

Do not replay an expired or stale Terraform plan. Revert the infrastructure
commit, inspect the new `terraform plan`, apply to staging, verify it, approve
the production job manually, then apply production. Terraform state remains in
the S3 backend and must not be edited by hand.

## Failed deployment checklist

1. Read the failed job and ECS service events.
2. Confirm the task definition references the intended commit-SHA image.
3. Check CloudWatch logs and task stop reasons.
4. Roll back to the previous known-good task/image if ECS cannot stabilize.
5. Fix the cause on a branch and repeat the full CI/CD path through staging.

Useful commands:

```bash
aws ecs describe-services --cluster <cluster> --services <service>
aws ecs list-tasks --cluster <cluster> --service-name <service>
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn>
aws logs tail <log-group> --since 30m
```
