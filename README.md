# Infrastructure as Code (IaC) Automation Repository

This repository contains the central Ansible Monorepo for automating and managing a hybrid infrastructure environment, consisting of a bare-metal desktop workstation (Arch/CachyOS) and a network-attached storage server (Debian).

The primary goal of this repository is to ensure **100% reproducibility, idempotency, and security** across all system levels, adhering to modern DevOps and Infrastructure as Code (IaC) standards.

---

## 🏛️ Architecture & Topology

The infrastructure is orchestrated from a single master playbook (`site.yml`) mapping roles dynamically via `inventory.ini`.

*   **Desktop Node (`desktops`)**: High-performance workstation running CachyOS (Arch Linux).
*   **Storage Node (`nas`)**: Debian-based server handling containerized workloads, automated backups, and file storage.

## 🎯 Design Principles

1.  **Strict Separation of Concerns**: This repository strictly manages system-level provisioning (packages, mounts, services, docker stacks). User-space configurations (Window Managers, Dotfiles, shell themes) are deliberately isolated in a separate, unprivileged dotfiles repository.
2.  **Idempotency**: All tasks are designed to be run multiple times without causing unintended side-effects. Hardware configurations (like BTRFS mounts) use UUID-agnostic filesystem labels (e.g., `LABEL=NAS-SSD`) to remain hardware-independent.
3.  **Zero-Leak Security**: No plaintext secrets, API keys, or `.env` files are tracked in version control. All sensitive data is managed via **Ansible Vault**.
4.  **Modular Execution**: Roles are highly cohesive and loosely coupled. Execution is governed by Ansible tags, allowing granular updates (e.g., updating only Docker containers without running base OS checks).

---

## 📦 Role Breakdown

### NAS Infrastructure (`nas`)

*   **`nas_storage`**: Automates BTRFS subvolume creation (SSD & HDD), MergerFS pooling (`/lib/immich`), and configures Snapper for automated snapshots.
*   **`nas_base`**: Bootstraps the core OS, configures DNS (`resolv.conf`), official Docker & NVIDIA repositories, `fail2ban`, `hdparm` spindown, and deploys a cross-platform Zsh environment.
*   **`nas_backups`**: Deploys multi-tiered backup strategies. Orchestrates transactional DB dumps (`pg_dumpall`, `sqlite3`), local BTRFS snapshot sync, cloud synchronization via Restic/Rclone, and SSD-to-HDD Immich tiering (`immich-mover.sh`).
*   **`nas_docker`**: Deploys the self-hosted application stack (Paperless-ngx, Ollama, Home Assistant + Matter, Prometheus, Grafana, Immich, Vaultwarden, AdGuard, Caddy, Cloudflared, Semaphore). Dynamically templates `docker-compose.yml` files and securely injects credentials at runtime.

### Desktop Infrastructure (`desktops`)

*   **`desktop_base`**: Configures the Arch/CachyOS baseline. Deploys package manager configurations (`pacman.conf`, `makepkg.conf`), the `greetd` display manager, `prometheus-node-exporter`, advanced Udev hardware rules, and automated snapshot backup timers.

---

## 📋 Prerequisites (Bootstrap)

Before running against fresh hardware, ensure the following baseline exists:
1.  **Ansible Collections**: Install required collections via `ansible-galaxy collection install -r requirements.yml`.
2.  **SSH & Sudo Access**: Passwordless or `--ask-become-pass` sudo privileges for user `kevin`, SSH public key deployed, and `nas-01` host key present in `~/.ssh/known_hosts`.
3.  **NAS Drivers & VPN**: NVIDIA proprietary kernel driver (`nvidia-driver` 550 for GTX 1070 Ti) and `tailscaled` logged in with **Key Expiry disabled**.
4.  **Restic Cloud Repository**: Initialized once via `restic init` for both `nas_restic_repo` and `homeserver_restic_repo`.

---

## 🔒 Secret Management (Ansible Vault)

To maintain public repository security, all credentials (database passwords, OAuth tokens, API keys) are stored in encrypted Ansible Vault files:
`group_vars/nas/secrets.yml` and `group_vars/desktops/secrets.yml`

These files are encrypted using AES-256. During deployment, Ansible decrypts them in-memory and injects the variables into Jinja2 templates (e.g., generating `.env` files for Docker containers).

### Managing Secrets
To view or edit the encrypted secrets, the Ansible Vault Master Password is required:
```bash
ansible-vault edit group_vars/nas/secrets.yml
```

---

## 🚀 Deployment & CI/CD Integration

This repository is designed to be executed both manually via the CLI and automatically via CI/CD pipelines (e.g., Ansible Semaphore).

### Manual Execution (CLI)

```bash
# Execute the full infrastructure deployment (without automatic dist-upgrade or image pulls)
ansible-playbook site.yml -i inventory.ini --ask-vault-pass --ask-become-pass

# Execute granular updates using tags (e.g., only update Docker configurations)
ansible-playbook nas.yml -i inventory.ini --ask-vault-pass --ask-become-pass --tags docker

# Explicitly pull new container images or run full apt dist-upgrade
ansible-playbook nas.yml -i inventory.ini --ask-vault-pass --ask-become-pass --tags docker,pull_images
ansible-playbook nas.yml -i inventory.ini --ask-vault-pass --ask-become-pass --tags base,system_upgrade
```

### Semaphore (CI/CD) Integration
When integrating with an automation UI like Semaphore:
1. Define a Key Store Credential for the **Vault Password** and **SSH Key / Become Password**.
2. Link this repository.
3. Create Task Templates pointing to `nas.yml` or `desktop.yml`. Use `--tags docker` (note: Semaphore automatically protects itself unless `infrastructure_only` is passed).
