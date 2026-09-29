# Shared CI templates

- `python-application.yml` provides compile/package, unit-test, and immutable
  Docker image publication jobs for the three Python services.
- `security.yml` blocks delivery when Bandit finds source-code issues or
  `pip-audit` finds vulnerable dependencies.
- `ecs-delivery.yml` provides staging deployment, verification, production
  approval, and production deployment jobs.
- `terraform.yml` provides the independent infrastructure pipeline.

Application repositories include the templates from
`crud-master/code-keeper` and define `SERVICE_NAME` plus the complete stage
order. Jobs run only for protected refs on the private `docker-private`
Runner. AWS credentials and registry coordinates are protected GitLab CI/CD
variables, never repository content.
