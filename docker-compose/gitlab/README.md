# GitLab (CE) + GitLab Runner (IPvlan + Synology Reverse Proxy)

Docker-Compose-Template fuer selbstgehostetes GitLab CE im **IPvlan** mit Synology **Reverse Proxy** fuer TLS-Termination.

## Was der Stack macht

- **gitlab** haengt mit einer festen IP im Heimnetz (macvlan `dockhand_macvlan`) und ist ueber die Synology Reverse Proxy per FQDN erreichbar.
- **gitlab-runner** laeuft in einem internen Bridge-Netz, das nur fuer die Kommunikation mit GitLab verwendet wird. Er holt CI/CD-Jobs ueber den Compose-internen DNS-Namen `gitlab` ab.

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
- Externes Netzwerk `dockhand_macvlan` als macvlan angelegt, Subnetz = Heimnetz, Gateway = Router (z. B. `192.168.178.1`).
- Genug Ressourcen: GitLab CE benoetigt mindestens **4 GB RAM** und **2-4 vCPU**; produktiv eher 8 GB+ RAM.
- Genug Speicherplatz in `data/` (Repos, LFS, Container-Registry-Daten etc.).
- **Reverse Proxy** ueber die Synology Application "Reverse Proxy" (DSM) oder NPM auf einer anderen Maschine. TLS-Termination erfolgt dort.
- DNS-Eintrag fuer den GitLab-FQDN (z. B. `gitlab.example.tld`) auf eine oeffentliche IP, Port-Forwarding 80/443 im Router.

## Netzwerk anlegen (macvlan, /24)

Auf Synology Container Manager ist `ipvlan` oft instabil und schlaegt mit
`failed to create the ipvlan port: operation not supported` fehl. Daher wird
`macvlan` empfohlen — Compose-File bleibt identisch, nur der Treiber beim
Anlegen des Netzes aendert sich.

**Wichtig**: Das Gateway muss innerhalb des gewaehlten Subnetzes liegen.
Da das Heimnetz typischerweise `192.168.178.0/24` ist, wird das macvlan-Netz
ebenfalls als `/24` angelegt, damit der echte Router als Gateway dient:

```bash
docker network create \
  --driver macvlan \
  --subnet 192.168.178.0/24 \
  --gateway 192.168.178.1 \
  --ip-range=192.168.178.160/27 \
  -o parent=eth0 \
  dockhand_macvlan
```

Den Wert fuer `parent=eth0` an das echte Interface anpassen
(`ip -br addr show` — oft `eth0`, `ovs_eth0` oder `bond0`).

## macvlan-Hinweise

- `GITLAB_IPV4` MUSS:
  - innerhalb des im Netz konfigurierten Subnetzes liegen,
  - **ausserhalb** des DHCP-Bereichs des Routers (statisch vergeben).
  - Beispiel: bei DHCP-Range `.2` - `.199` bietet sich `GITLAB_IPV4=192.168.178.200` an.
- macvlan-Container koennen das **Gateway ueblicherweise nicht direkt erreichen**
  (Layer-2-Isolation). Fuer ausgehende Verbindungen (z. B. SMTP, GitLab-Update)
  ggf. ein zweites Bridge-Netz ergaenzen.

## First-Run Checkliste

1. `.env.example` nach `.env` kopieren.
2. Folgende Werte in `.env` setzen:
   - `GITLAB_EXTERNAL_URL`: `https://<dein-fqdn>` (z. B. `https://gitlab.example.tld`).
   - `GITLAB_HOSTNAME`: gleicher FQDN.
   - `GITLAB_IPV4`: freie, statische IP aus dem `dockhand_macvlan`-Subnetz (ausserhalb DHCP).
   - `GITLAB_EMAIL_FROM`: Absender fuer System-Mails.
   - `GITLAB_SSH_PORT`: ein Port ungleich 22 (Synology belegt 22). Empfehlung: `2222`.
3. Synology **Reverse Proxy** anlegen (siehe unten).
4. Firewall der Synology: Port `GITLAB_SSH_PORT` und (intern) Zugriff vom Reverse-Proxy auf `GITLAB_IPV4:80` erlauben.
5. Optional SMTP-Block in `GITLAB_OMNIBUS_CONFIG` einkommentieren und Werte setzen.
6. Stack starten — **Initial-Start dauert 3-10 Minuten**.

## Wichtige `.env` Einstellungen

In `.env` stehen ausschliesslich die **pro Deployment anzupassenden, host-spezifischen** Werte. Image-Tags, Container-Namen, `shm_size` und Netzwerknamen sind fest in `docker-compose.yml` hinterlegt.

- `GITLAB_EXTERNAL_URL`: `https://<fqdn>` — wird fuer Clone-URLs und Web-Links genutzt.
- `GITLAB_HOSTNAME`: interner Hostname des Containers, meist identisch mit FQDN.
- `GITLAB_IPV4`: statische IPv4 aus dem `dockhand_macvlan`-Subnetz (muss ausserhalb DHCP).
- `GITLAB_EMAIL_FROM`: Absender fuer System-Mails.
- `GITLAB_SSH_PORT`: SSH-Container-Port (nicht 22 waehlen, Synology belegt ihn).

Hinweis: Subnetz, Gateway und Parent-Interface sind **nicht** in `.env`, sondern direkt im `dockhand_macvlan`-Netzwerk auf dem Docker-Host hinterlegt.

## Im Compose festgelegte Defaults

- `gitlab/gitlab-ce:17.9.1-ce.0` und `gitlab/gitlab-runner:alpine-v17.9.1` (Minor-Version gepinnt)
- Container-Namen: `gitlab` und `gitlab-runner`
- `shm_size: 256m` (GitLab-Empfehlung)

## Synology Reverse Proxy einrichten

In der **DSM-Systemsteuerung -> Anmeldeportal -> Erweitert -> Reverse Proxy**:

1. **Regel anlegen**:
   - Quelle: `https://gitlab.example.tld` Port `443`
   - Ziel: `http://<GITLAB_IPV4>` Port `80`
   - Haken bei "HSTS" und "HTTP/2"

2. **WebSocket-Unterstuetzung** aktivieren, da GitLab WebSockets fuer Live-Updates, Terminal etc. verwendet.

3. **Zertifikat**: In DSM -> Systemsteuerung -> Sicherheit -> Zertifikat ein passendes Let's-Encrypt-Zertifikat fuer den FQDN hinterlegen und der Reverse-Proxy-Regel zuweisen.

4. **SSH-Port (`GITLAB_SSH_PORT`)**: Im Router zur Synology weiterleiten. GitLab-Container hoert intern auf 22 und ist ueber `GITLAB_IPV4:22` erreichbar.

**Wichtig**: GitLab NGINX hoert im Container **nur** auf `GITLAB_IPV4` (siehe `nginx['listen_addresses']` in `docker-compose.yml`). Der Reverse-Proxy muss daher zwingend diese IP ansprechen.

## Starten

```bash
cd docker-compose/gitlab
cp .env.example .env
# .env anpassen
docker compose pull
docker compose up -d
```

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
- Der Runner laeuft im Bridge-Netz `gitlab-internal` und kann den GitLab-Server ueber `http://gitlab` erreichen.
- Tags/Executor je nach Use-Case anpassen.

## Zugriff

- Web-UI: `https://<dein-fqdn>` (ueber Synology Reverse Proxy)
- Git ueber HTTP(S): `https://<dein-fqdn>/<group>/<project>.git`
- Git ueber SSH: `ssh://git@<dein-fqdn>:<GITLAB_SSH_PORT>/<group>/<project>.git`
- Initiales root-Passwort aus dem Container auslesen:

```bash
docker exec -it gitlab cat /etc/gitlab/initial_root_password
```

> Hinweis: `initial_root_password` wird aus Sicherheitsgruenden nach **24 Stunden** automatisch geloescht. Danach Passwort ueber die Web-UI oder ueber `gitlab-rake` zuruecksetzen.
