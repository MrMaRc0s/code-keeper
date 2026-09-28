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

Milestone 1 deploys the self-hosted GitLab instance. Install the pinned Ansible
collection, create the local inventory and encrypted vault, then run the
playbook from the `ansible` directory:

```bash
ansible-galaxy collection install -r requirements.yml
cp inventories/hosts.yml.example inventories/hosts.yml
cp vault.example.yml vault.yml
ansible-vault encrypt vault.yml
ansible-playbook playbooks/deploy-gitlab.yml \
  --ask-vault-pass \
  --extra-vars '@vault.yml'
```

The submitted inventory and vault files contain placeholders only. The real
files are ignored by Git.

## Security rule

Credentials, access tokens, Ansible Vault passwords, Terraform state, and
generated plans must never be committed. Only example files containing
placeholders belong in this repository.
