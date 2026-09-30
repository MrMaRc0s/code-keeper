#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: deploy-ecs-service.sh <environment> <service> <image-uri> <container-name>

Registers a new ECS task-definition revision for <service> (in the
"<project>-<environment>-cluster" ECS cluster) with <container-name>'s
image replaced by <image-uri>, updates the service to that revision, and
waits for the deployment to stabilize. Never builds or pushes an image -
<image-uri> must already exist in ECR; that's containerize's job, not
this script's.

On failure, prints the exact rollback command to restore the previous
task-definition revision and returns non-zero. It does not roll back
automatically - a human decides whether that's the right move.

Environment variables:
  PROJECT_NAME   Defaults to "cloud-design".
  AWS_REGION     Required (or already exported for the AWS CLI).

Requires: bash, AWS CLI, jq.
USAGE
}

if [ $# -ne 4 ]; then
  usage
  exit 1
fi

environment="$1"
service="$2"
image_uri="$3"
container_name="$4"
project_name="${PROJECT_NAME:-cloud-design}"
cluster="${project_name}-${environment}-cluster"

for dependency in aws jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Error: $dependency is required but not found on PATH" >&2
    exit 1
  fi
done

echo "Reading current task definition for service ${service} in ${cluster}..."
current_task_def_arn=$(aws ecs describe-services \
  --cluster "$cluster" \
  --services "$service" \
  --query 'services[0].taskDefinition' \
  --output text)

if [ -z "$current_task_def_arn" ] || [ "$current_task_def_arn" = "None" ]; then
  echo "Error: could not find a running task definition for service ${service} in ${cluster}" >&2
  exit 1
fi

echo "Current task definition: ${current_task_def_arn}"

current_task_def=$(aws ecs describe-task-definition \
  --task-definition "$current_task_def_arn" \
  --query 'taskDefinition')

# Only the named container's image changes - every other setting (cpu,
# memory, roles, log config, health check, other containers) carries over
# untouched.
new_container_definitions=$(echo "$current_task_def" | jq --arg name "$container_name" --arg image "$image_uri" '
  .containerDefinitions |= map(if .name == $name then .image = $image else . end)
')

if ! echo "$new_container_definitions" | jq -e --arg name "$container_name" '.containerDefinitions[] | select(.name == $name)' >/dev/null; then
  echo "Error: no container named '${container_name}' in the current task definition" >&2
  exit 1
fi

# describe-task-definition returns several read-only/derived fields
# (taskDefinitionArn, revision, status, requiresAttributes, compatibilities,
# registeredAt, registeredBy, ...) that register-task-definition rejects if
# passed straight back - keep only the fields it actually accepts.
register_input=$(echo "$new_container_definitions" | jq '{
  family: .family,
  containerDefinitions: .containerDefinitions,
  taskRoleArn: .taskRoleArn,
  executionRoleArn: .executionRoleArn,
  networkMode: .networkMode,
  volumes: .volumes,
  placementConstraints: .placementConstraints,
  requiresCompatibilities: .requiresCompatibilities,
  cpu: .cpu,
  memory: .memory
} | with_entries(select(.value != null))')

echo "Registering new task definition revision..."
new_task_def_arn=$(aws ecs register-task-definition \
  --cli-input-json "$register_input" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "New task definition: ${new_task_def_arn}"

echo "Updating service ${service}..."
aws ecs update-service \
  --cluster "$cluster" \
  --service "$service" \
  --task-definition "$new_task_def_arn" \
  >/dev/null

echo "Waiting for the service to stabilize..."
if ! aws ecs wait services-stable --cluster "$cluster" --services "$service"; then
  echo "Error: service ${service} did not stabilize on ${new_task_def_arn}" >&2
  echo "Rollback: aws ecs update-service --cluster ${cluster} --service ${service} --task-definition ${current_task_def_arn}" >&2
  exit 1
fi

echo "Deployed ${container_name}=${image_uri} to ${service} in ${cluster} (${new_task_def_arn})."
