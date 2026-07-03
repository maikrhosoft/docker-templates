# GitLab (CE) + GitLab Runner (Bridge + Synology Reverse Proxy)

Docker-Compose-Template fuer selbstgehostetes GitLab CE im **Bridge-Modus** mit Synology **Reverse Proxy** fuer TLS-Termination.

## Was der Stack macht

- **gitlab** liegt in einem Bridge-Netz und exponiert HTTP/HTTPS/SSH ueber konfigurierbare Host-Ports.
- **gitlab-runner** laeuft in einem **internen** Bridge-Netz ohne Host-Ports und holt CI/CD-Jobs ueber den Compose-internen DNS-Namen `gitlab` ab.
- Der Synology Reverse Proxy spricht GitLab ueber die Host-Ports (Standard: `127.0.0.1:8080`) an und terminiert TLS.

## Verzeichnisstruktur

```text
gitlab/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
├── config/      # /etc/gitlab
├── logs/        # /var/log/gitlab
├── data/        # /var/opt/gitlab (Repos, DB, Objektspeicher)
├── backups/     # Backup-Ablage (gitlab_rails['backup_path'])
└── runner/
    └── config/  # /etc/gitlab-runner
```

## Voraussetzungen

- Docker + Compose Plugin auf der Synology (Container Manager) installiert.
- Genug Ressourcen: GitLab CE benoetigt mindestens **4 GB RAM** und **2-4 vCPU**; produktiv eher 8 GB+ RAM.
- Genug Speicherplatz in `data/` (Repos, LFS, Container-Registry-Daten etc.).
- **Reverse Proxy** ueber die Synology Application "Reverse Proxy" (DSM) oder NPM auf einer anderen Maschine. TLS-Termination erfolgt dort.
- DNS-Eintrag fuer den GitLab-FQDN (z. B. `gitlab.example.tld`) auf eine oeffentliche IP, Port-Forwarding 80/443 im Router.

## Netzwerk

- `gitlab-bridge` (Bridge): GitLab hoert auf den Host-Ports `GITLAB_SSH_HOST_PORT` (Container 22), `GITLAB_HTTP_HOST_PORT` (Container 80), `GITLAB_HTTPS_HOST_PORT` (Container 443). Der Synology Reverse Proxy spricht GitLab ueber `http://127.0.0.1:${GITLAB_HTTP_HOST_PORT}` an.
- `gitlab-internal` (Bridge, ohne externe Erreichbarkeit): nur fuer die Kommunikation GitLab <-> Runner. Runner registriert sich ueber `http://gitlab` (Service-Name im internen Netz).
- Es ist **kein** externes Netzwerk oder IPvlan/macvlan noetig.

## First-Run Checkliste

1. `.env.example` nach `.env` kopieren.
2. Folgende Werte in `.env` setzen:
   - `GITLAB_EXTERNAL_URL`: `https://<dein-fqdn>` (z. B. `https://gitlab.example.tld`).
   - `GITLAB_HOSTNAME`: gleicher FQDN.
   - `GITLAB_EMAIL_FROM`: Absender fuer System-Mails.
   - `GITLAB_SSH_HOST_PORT`, `GITLAB_HTTP_HOST_PORT`, `GITLAB_HTTPS_HOST_PORT`: Host-Ports. Standard `2222`, `8080`, `8443`. Bei Port-Kollisionen anpassen.
3. Synology **Reverse Proxy** anlegen (siehe unten).
4. Firewall der Synology: Host-Ports `GITLAB_SSH_HOST_PORT`, `GITLAB_HTTP_HOST_PORT`, `GITLAB_HTTPS_HOST_PORT` freigeben.
5. Optionale Konfigurationen (SMTP etc.) koennen nach dem Start ueber `gitlab-rails console` oder eine lokale `config/gitlab.rb` gesetzt werden (siehe unten).
6. Stack starten — **Initial-Start dauert 3-10 Minuten**.

## Wichtige `.env` Einstellungen

In `.env` stehen ausschliesslich die **pro Deployment anzupassenden, host-spezifischen** Werte. Image-Tags, Container-Namen und `shm_size` sind fest in `docker-compose.yml` hinterlegt.

- `GITLAB_EXTERNAL_URL`: `https://<fqdn>` — wird fuer Clone-URLs und Web-Links genutzt.
- `GITLAB_HOSTNAME`: interner Hostname des Containers, meist identisch mit FQDN.
- `GITLAB_EMAIL_FROM`: Absender fuer System-Mails.
- `GITLAB_BRIDGE_NETWORK_NAME`: Name des Bridge-Netzes (Default: `gitlab-bridge`).
- `GITLAB_SSH_HOST_PORT`: Host-Port, ueber den SSH-Clients GitLab erreichen (Default: `2222`). Wird intern auch fuer `gitlab_shell_ssh_port` verwendet, sodass Clone-URLs korrekt angezeigt werden.
- `GITLAB_HTTP_HOST_PORT`: Host-Port fuer HTTP (Default: `8080`). Wird vom Synology Reverse Proxy angesprochen.
- `GITLAB_HTTPS_HOST_PORT`: Host-Port fuer HTTPS (Default: `8443`).

## Im Compose festgelegte Defaults

- `gitlab/gitlab-ce:17.9.1-ce.0` und `gitlab/gitlab-runner:alpine-v17.9.1` (Minor-Version gepinnt)
- Container-Namen: `gitlab` und `gitlab-runner`
- `shm_size: 256m` (GitLab-Empfehlung)

## Synology Reverse Proxy einrichten

In der **DSM-Systemsteuerung -> Anmeldeportal -> Erweitert -> Reverse Proxy**:

1. **Regel anlegen**:
   - Quelle: `https://gitlab.example.tld` Port `443`
   - Ziel: `http://127.0.0.1` Port `8080` (entspricht `GITLAB_HTTP_HOST_PORT`)
   - Haken bei "HSTS" und "HTTP/2"

2. **WebSocket-Unterstuetzung** aktivieren, da GitLab WebSockets fuer Live-Updates, Terminal etc. verwendet.

3. **Zertifikat**: In DSM -> Systemsteuerung -> Sicherheit -> Zertifikat ein passendes Let's-Encrypt-Zertifikat fuer den FQDN hinterlegen und der Reverse-Proxy-Regel zuweisen.

4. **SSH-Port (`GITLAB_SSH_HOST_PORT`)**: Im Router zur Synology weiterleiten. GitLab lauscht intern immer auf Container-Port 22 — der konfigurierbare Host-Port wird in den Clone-URLs automatisch uebernommen.

**Wichtig**: Der Reverse-Proxy spricht GitLab ueber `127.0.0.1:${GITLAB_HTTP_HOST_PORT}` an (Standard `8080`). Bei Aenderung von `GITLAB_HTTP_HOST_PORT` die Reverse-Proxy-Regel mit anpassen.

## Starten

```bash
cd docker-compose/gitlab
cp .env.example .env
# .env anpassen
docker compose pull
docker compose up -d
```

## Optionale Konfigurationen (SMTP, etc.)

Da der Stack per Dockhand direkt aus dem Git-Repo geladen wird, sind SMTP
und andere erweiterte Einstellungen **nicht** Teil des compose-Files. Es
gibt zwei Wege, sie zu setzen — **ohne das compose-File zu editieren**:

### Variante 1: Per `gitlab-rails console` (interaktiv)

Fuer schnelle Tests, dauerhafte Aenderungen per Reconfigure:

```bash
docker exec -it gitlab gitlab-rails console
```

Innerhalb der Console z. B. SMTP setzen:

```ruby
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
  address:              "smtp.example.com",
  port:                 587,
  user_name:            "user",
  password:             "pass",
  domain:               "example.com",
  authentication:       "login",
  enable_starttls_auto: true
}
ApplicationSetting.first.update!(email_from: "gitlab@example.com")
exit
```

Danach `gitlab-ctl reconfigure` ausfuehren.

### Variante 2: `gitlab.rb` als File mounten (fuer dauerhafte Aenderungen)

1. Lokal `gitlab.rb` unter `config/gitlab.rb` anlegen (im selben Verzeichnis wie `docker-compose.yml`).
2. Dort z. B. SMTP-Einstellungen eintragen:

   ```ruby
   gitlab_rails['smtp_enable'] = true
   gitlab_rails['smtp_address'] = "smtp.example.com"
   gitlab_rails['smtp_port'] = 587
   gitlab_rails['smtp_user_name'] = "user"
   gitlab_rails['smtp_password'] = "pass"
   gitlab_rails['smtp_domain'] = "example.com"
   gitlab_rails['smtp_authentication'] = "login"
   gitlab_rails['smtp_enable_starttls_auto'] = true
   ```

3. In `docker-compose.yml` unter `volumes:` zusaetzlich mounten:

   ```yaml
   volumes:
     - ./config:/etc/gitlab
     - ./config/gitlab.rb:/etc/gitlab/gitlab.rb
   ```

   **Reihenfolge ist wichtig**: Der spezifische Mount kommt **nach** dem Verzeichnis-Mount, sonst wird er vom Verzeichnis-Mount ueberlagert.

4. `docker compose up -d` und `docker exec -it gitlab gitlab-ctl reconfigure`.

Die Datei `config/gitlab.rb` ist ueber Synology File Station oder jeden
Texteditor editierbar, ohne das compose-File anzufassen.

## Status und Logs

```bash
docker compose ps
docker compose logs -f gitlab
docker compose logs -f gitlab-runner
```

Pruefen, ob GitLab bereit ist (im Container):

```bash
docker exec -it gitlab gitlab-ctl status
docker exec -it gitlab gitlab-rake gitlab:check SANITIZE=true
```

Erreichbarkeit aus dem Container testen:

```bash
docker exec -it gitlab curl -I http://127.0.0.1
```

## Stoppen

```bash
docker compose down
```

## Update

```bash
cd docker-compose/gitlab
# Neue Version in docker-compose.yml setzen (image: ...)
docker compose pull
docker compose up -d
```

Fuer grosse Versionsspruenge (z. B. 16.x -> 17.x) GitLab-Update-Dokumentation beachten: https://docs.gitlab.com/ee/update/

## Backup

Im Container:

```bash
docker exec -t gitlab gitlab-backup create
```

Backups landen in `backups/` (siehe `backup_path` in `GITLAB_OMNIBUS_CONFIG`).

Vollstaendiges Restore (Konfig + Daten + Backup): https://docs.gitlab.com/ee/raketasks/backup_restore.html#restore-for-omnibus-gitlab-installations

## Persistente Daten (Backup)

Diese Verzeichnisse regelmaessig sichern:
- `config/`
- `data/`
- `logs/`
- `backups/`
- `runner/config/`

## GitLab Runner registrieren

1. In GitLab als Admin: `Admin -> CI/CD -> Runners -> New project runner` (oder Instance-Runner) anlegen.
2. Registrierungstoken kopieren.
3. Runner registrieren (intern ueber Compose-DNS):

```bash
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab" \
  --registration-token "<TOKEN>" \
  --executor "docker" \
  --docker-image "docker:24" \
  --docker-privileged=false \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --description "docker-runner" \
  --tag-list "docker" \
  --run-untagged=false
```

Hinweise:
- `--url` zeigt auf den internen DNS-Namen `gitlab` im Compose-Netz. Die externe FQDN ist hier **nicht** noetig.
- Der Runner laeuft im internen Bridge-Netz `gitlab-internal` und kann den GitLab-Server ueber `http://gitlab` erreichen.
- Tags/Executor je nach Use-Case anpassen.

## Zugriff

- Web-UI: `https://<dein-fqdn>` (ueber Synology Reverse Proxy)
- Git ueber HTTP(S): `https://<dein-fqdn>/<group>/<project>.git`
- Git ueber SSH: `ssh://git@<dein-fqdn>:<GITLAB_SSH_HOST_PORT>/<group>/<project>.git`
- Direkt auf der Synology (z. B. zu Testzwecken): `http://127.0.0.1:${GITLAB_HTTP_HOST_PORT}`
- Initiales root-Passwort aus dem Container auslesen:

```bash
docker exec -it gitlab cat /etc/gitlab/initial_root_password
```

> Hinweis: `initial_root_password` wird aus Sicherheitsgruenden nach **24 Stunden** automatisch geloescht. Danach Passwort ueber die Web-UI oder ueber `gitlab-rake` zuruecksetzen.
