# Sovereign Infrastructure

This repository contains the complete Infrastructure-as-Code (IaC) setup for a modern, hybrid homelab and desktop environment. It uses **Ansible** to deterministically configure bare-metal systems (Debian NAS and CachyOS Desktop) from a minimal installation up to a fully running, containerized, and backed-up state.

## 🏗️ Architecture & Roles

The infrastructure is split into specific, modular roles. The `site.yml` playbook maps these roles to the respective hosts defined in `inventory.ini`.

### NAS Roles (`nas-01` - Debian)
*   **`nas_storage`**: Idempotently mounts specific BTRFS subvolumes via labels (e.g., `LABEL=NAS-SSD`) and creates them if they don't exist. Manages `mergerfs` pools and configures `snapper` templates.
*   **`nas_base`**: Installs essential system packages, configures base DNS (e.g., `resolv.conf`), and deploys a cross-platform Zsh environment.
*   **`nas_backups`**: Deploys dynamic sync scripts (Restic/Rclone) and configures Systemd timers. Includes dynamic block-device discovery to gracefully spin down HDDs (via `hdparm`).
*   **`nas_docker`**: Manages the core self-hosted stack (Paperless, Grafana, Prometheus, Home Assistant, Vaultwarden, Immich). It dynamically templates `docker-compose.yml` and securely injects `.env` files via Ansible Vault.

### Desktop Roles (`homeserver` - CachyOS/Arch)
*   **`desktop_base`**: Configures the Arch/CachyOS baseline. Deploys package manager configurations (`pacman.conf`, `makepkg.conf`), the `greetd` display manager, specific udev rules, and maintenance routines (like `paru` cache cleanup and btrfs snapshot timers).

## 🔒 Secret Management (Zero-Leak Policy)

This repository follows a strict Zero-Leak Policy. No plaintext passwords, API keys, or `.env` files are tracked in Git.
Instead, all secrets are stored in a single encrypted file:
`group_vars/nas/secrets.yml`

This file is encrypted using **Ansible Vault** (AES-256).

### Decrypting / Editing Secrets
To edit the secrets or add new ones:
```bash
ansible-vault edit group_vars/nas/secrets.yml
```

## 🚀 How to Use / Deploy

### Prerequisites
1. A fresh Debian / Arch (CachyOS) installation.
2. Ansible installed on the control node.
3. Your Ansible Vault Master Password.

### Deployment
To execute the playbook across your infrastructure:

```bash
# Clone the repository
git clone git@github.com:reitererkvn/infrastructure.git /opt/infrastructure
cd /opt/infrastructure

# Run the master playbook
ansible-playbook site.yml -i inventory.ini --ask-vault-pass
```

## 🛠️ For Others (Adapting this Repo)

If you are a developer looking to use this setup as a template for your own homelab:
1.  **Inventory:** Update `inventory.ini` with your own IP addresses and hostnames.
2.  **Storage:** Review `roles/nas_storage/tasks/main.yml`. Adjust the `LABEL=...` variables to match your actual filesystem labels.
3.  **Secrets:** Overwrite `group_vars/nas/secrets.yml` with your own Ansible Vault file.
4.  **Desktop Configs:** Review `roles/desktop_base/files/etc/pacman.conf` and `udev/rules.d/` as they contain hardware-specific configurations (like specific gaming mice reset rules).

## 🗑️ Separation of Concerns
This repository ONLY handles system-level configuration and infrastructure provisioning (Root/Admin Space).
User-specific dotfiles (like Window Manager configs, Editor settings, aliases) are strictly separated and managed via a dedicated dotfiles repository in the User Space (`~/.dotfiles`).
