# Code Keeper

Automation and shared CI/CD resources for a self-hosted GitLab platform that
builds, scans, and deploys the CRUD Master microservices to AWS staging and
production environments.

The final platform contains four independent GitLab projects:

- `inventory-app`
- `billing-app`
- `api-gateway-app`
- `cloud-infrastructure`

This control repository contains the Ansible roles used to deploy GitLab and
GitLab Runner, reusable pipeline templates, deployment scripts, and the audit
runbook. Application source and Terraform infrastructure remain in their own
repositories as required by the subject.

## Current milestone

Milestone 0 defines the shared contract and the reproducible repository
structure. GitLab deployment instructions will be added with the Ansible
roles in the next milestone.

## Security rule

Credentials, access tokens, Ansible Vault passwords, Terraform state, and
generated plans must never be committed. Only example files containing
placeholders belong in this repository.

