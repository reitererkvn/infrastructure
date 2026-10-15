# NAS Docker Stack (`nas_docker`)

Diese Rolle verwaltet und automatisiert die Docker-Container-Infrastruktur auf dem Debian NAS (`nas-01`). Alle Compose-Konfigurationen werden aus `templates/compose/{{ item }}.yml.j2` generiert, secrets dynamisch aus `group_vars/nas/secrets.yml` als `.env` injiziert und alle Webservices über das gemeinsame Docker-Netzwerk `proxy_net` verbunden.

---

## 🚀 Verwaltete Services

| Service | Container-Name | Port(s) / Interne URL | Zweck / Abhängigkeiten |
| :--- | :--- | :--- | :--- |
| **Semaphore** | `semaphore`, `semaphore-db` | `3000` (Web UI via Caddy) | Web-basiertes UI zur Ausführung von Ansible Playbooks. |
| **Paperless-ngx** | `paperless_webserver`, `paperless_db`, `paperless_redis` | `8002` (Web UI via Caddy) | Dokumentenmanagement & OCR. Nutzt GPU für Beschleunigung und **Ollama** für Text-Embeddings. |
| **Ollama** | `ollama` | `11434` (`http://ollama:11434`) | Lokale LLM- & Embedding-Inferenz via NVIDIA CUDA (GTX 1070 Ti). Stellt u.a. `mxbai-embed-large` für Paperless bereit. |
| **Immich** | `immich_server`, `immich_machine_learning`, `immich_postgres`, `immich_redis` | `2285` (Web UI via Caddy) | Selbst gehostetes Foto- und Video-Backup mit KI-gestützter Objekterkennung (CUDA). |
| **Home Assistant** | `homeassistant`, `matter-server` | Host-Netzwerk (`8123`) | Hausautomatisierung & Matter/Thread Border Controller. |
| **Vaultwarden** | `vaultwarden` | `8000` (Web UI via Caddy) | Bitwarden-kompatibler Passwort-Tresor. |
| **AdGuard Home** | `adguard` | `53` (DNS), `3002` (Web UI) | Lokaler DNS- & Ad-Blocker. |
| **Caddy** | `caddy` | Host-Netzwerk (`80`, `443`) | Reverse Proxy mit automatischem TLS via Cloudflare DNS / Tailscale. |
| **Monitoring** | `prometheus`, `grafana`, `node-exporter-nas` | `9090`, `3001`, `9101` | Metriken und Systemdashboards. |
| **Cloudflared** | `cloudflared` | Host-Netzwerk | Cloudflare Zero Trust Tunnel für sichere externe Endpunkte. |

---

## 🧠 Ollama Integration & Modellverwaltung

Ollama läuft containerisiert mit NVIDIA-GPU-Passthrough (`capabilities: [gpu, video, compute, utility]`) und ist sowohl im `proxy_net` erreichbar (`http://ollama:11434`) als auch auf dem Host gebunden (`11434:11434`).

### Zusammenspiel mit Paperless-ngx
Paperless-ngx nutzt Ollama als dedizierten Embedding-Provider für KI-Vektor-Suche und automatische Klassifizierung:
* **Modell:** `mxbai-embed-large`
* **Endpunkt:** `http://ollama:11434` (oder `http://192.168.178.46:11434`)
* **Wichtig:** Wenn Ollama nicht verfügbar ist oder der GPU-Treiber fehlschlägt, blockieren Paperless-Ingest-Worker bei der Verarbeitung von Dokumenten.

### Modell manuell pullen / überprüfen
```bash
# Verfügbare Modelle auflisten
docker exec ollama ollama list

# Erforderliches Embedding-Modell für Paperless laden
docker exec ollama ollama pull mxbai-embed-large
```

---

## ⚠️ Bekannte Fallstricke

1. **Kernel-Updates & NVIDIA-Treiber:**
   * Nach Debian-Kernel-Updates muss das DKMS-Modul (`nvidia-current`) für den neuen Kernel gebaut sein (`dkms status`).
   * Ist das Modul nicht geladen, schlagen alle Container mit GPU-Reservierungen (`ollama`, `immich_machine_learning`, `paperless_webserver`, `homeassistant`) beim Start mit Exit-Code 128 (`driver not loaded`) fehl.
2. **Semaphore UI & Upstream-Releases:**
   * Semaphore UI darf bei Schema-Migrationen nicht durch ältere Zwischenversionen downgegradet werden, da Go-ORM (`gorp`) sonst bei unbekannten Spalten Fehler 400 wirft.
