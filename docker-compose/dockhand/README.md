# Dockhand (Docker Swarm + Traefik)

Docker-Compose-Template fuer [Dockhand](https://github.com/fnsys/dockhand) als Single-Container-Service mit Docker-Socket-Zugriff, Traefik-Labels und Persistenz ueber ein lokales Bind-Mount.

## Was der Stack macht

- **dockhand** ist ein Container-Management-Web-UI, das den Docker-Socket des Hosts einbindet und damit auf alle Stacks/Services des Hosts zugreifen kann.
- **Traefik** (externer Reverse-Proxy, nicht im Stack enthalten) liest die Labels am Service und routet HTTPS fuer `dockhand.example.com` auf den Container-Port `3000`.
- Persistenz erfolgt ueber `./data` als Bind-Mount — kein benanntes Volume, einfache Backups per `tar`/`rsync`.

---

## Verzeichnisstruktur

```text
dockhand/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
└── data/        # /app/data (Anwendungsdaten)
```

## Voraussetzungen

- Docker Engine mit aktiviertem **Swarm-Modus** (`docker swarm init` auf einem Manager-Node).
- Dockhand laeuft zwingend auf einem **Manager-Node**, weil der Docker-Socket gemountet wird.
- Externes Overlay-Netz `proxy` existiert (`docker network create --driver=overlay proxy`). Traefik muss ebenfalls an diesem Netz haengen.
- Optional: DNS-Eintrag fuer `dockhand.example.com` auf eine oeffentliche IP und Port-Forwarding 80/443 im Router.

## Netzwerk

- `dockhand-internal` (Overlay, vom Stack angelegt): internes Netz fuer Dockhand. Wird im Standalone-`docker compose`-Modus ignoriert bzw. als Bridge angelegt.
- `proxy` (Overlay, **extern**, `name: proxy`): gemeinsames Netz mit Traefik. Muss vor `docker stack deploy` manuell angelegt sein, sonst schlaegt das Deploy fehl.

---

## First-Run Checkliste

1. `cd docker-compose/dockhand` und `cp .env.example .env`.
2. In `docker-compose.yml` die Traefik-Domain anpassen: `dockhand.example.com` durch den eigenen FQDN ersetzen (mehrere Stellen, siehe Sektion "Traefik-Labels").
3. Sicherstellen, dass `DOCKHAND_HOST_PORT` (Default `3000`) nicht mit anderen lokalen Diensten kollidiert — Traefik spricht Dockhand ueber das `proxy`-Netz an, der Host-Port ist nur fuer den Direktzugriff ohne Traefik relevant.
4. Pruefen, dass das externe Netz `proxy` existiert: `docker network ls | grep proxy` — falls nicht: `docker network create --driver=overlay proxy` (Swarm-Modus) bzw. `docker network create proxy` (Standalone).
5. Stack deployen: `docker stack deploy -c docker-compose.yml dockhand` (Swarm) oder `docker compose up -d` (lokal).

## Wichtige `.env` Einstellungen

| Variable | Default | Bedeutung |
| --- | --- | --- |
| `DOCKHAND_HOST_PORT` | `3000` | Host-Port, ueber den Dockhand ohne Traefik direkt erreichbar ist. Container horcht intern auf `3000`. |
| `DOCKHAND_IMAGE_TAG` | `latest` | Image-Tag von `fnsys/dockhand`. Fuer reproduzierbare Deploys auf einen konkreten Tag pinnen. |

## Im Compose festgelegte Defaults

- Image: `fnsys/dockhand:${DOCKHAND_IMAGE_TAG}` (Tag konfigurierbar)
- Container-Name: `dockhand`
- Container-Port: `3000` (Image-Default)
- `restart: unless-stopped`
- `healthcheck`: `wget --spider http://localhost:3000/health`, `interval: 30s`, `timeout: 5s`, `retries: 3`, `start_period: 30s`. Siehe Sektion "Healthcheck".
- Traefik-Labels: `Host(`dockhand.example.com`)`, Entrypoint `websecure`, `certresolver=letsencrypt`, Backend-Port `3000`. **Domain anpassen** in `docker-compose.yml` (siehe Sektion "Traefik-Labels").
- `deploy:`-Block (Swarm): `replicas: 1`, Placement-Constraint `node.role == manager`, `restart_policy: condition: any`. Wird im Standalone-`docker compose`-Modus ignoriert.

---

## Sicherheitshinweis: Docker-Socket

Der Service mounted `/var/run/docker.sock` in den Container. Damit erhaelt der Prozess im Container **vollen Root-Zugriff auf den Docker-Daemon** des Hosts — und damit auf alle Container, Images, Volumes und Netzwerke des Hosts.

Konsequenzen:

- Eine Schwachstelle in Dockhand (oder in einem seiner Dependencies) ist effektiv eine **Schwachstelle auf dem Host**.
- Wer Zugriff auf die Web-UI hat, kann beliebige Container starten/stoppen, Images pullen und in andere Netze einbrechen.

Empfehlungen:

- Dockhand **nur** auf einem dedizierten Manager-Node betreiben, nicht auf allen Nodes.
- Web-UI **zwingend hinter Traefik mit Authentifizierung** (z. B. Traefik `forwardAuth` mit Authelia/Authentik) betreiben — nicht oeffentlich erreichbar machen.
- Image regelmaessig updaten (`docker service update --image` bzw. `docker compose pull && docker compose up -d`), um bekannte CVEs zu schliessen.
- Pruefen, ob das Image in der Zwischenzeit einen "read-only" oder "rootless"-Modus unterstuetzt (siehe Upstream-README).

## Traefik-Labels

Die Traefik-Labels sind additiv: **ohne laufenden Traefik-Stack sind sie inert** und haben keine Nebenwirkungen. Traefik scannt nur Services, die es ueber seinen Provider (hier: Docker) entdeckt.

Vor dem Deploy anpassen:

- `traefik.http.routers.dockhand.rule=Host(`dockhand.example.com`)` — Domain auf den eigenen FQDN aendern.
- Pruefen, dass `entrypoints=websecure` und `certresolver=letsencrypt` zu den in Traefik konfigurierten Entrypoints/Certresolvern passen.
- `traefik.docker.network=proxy` ist noetig, weil der Container an **mehreren** Netzen haengt. Traefik muss wissen, ueber welches Netz es den Container erreicht.

Workaround ohne Traefik: ueber den Host-Port `http://<host>:<DOCKHAND_HOST_PORT>` direkt auf die Web-UI zugreifen (z. B. im LAN ohne TLS).

---

## Healthcheck

Der Service hat einen `healthcheck:`-Block in `docker-compose.yml`, der den internen Endpunkt `http://localhost:3000/health` per `wget` prueft. Standard-Parameter:

- `interval: 30s` — Pruef-Intervall
- `timeout: 5s` — Timeout pro Pruefung
- `retries: 3` — Anzahl Fehlversuche, bis der Container als `unhealthy` gilt
- `start_period: 30s` — Karenzzeit nach Container-Start, in der Fehler nicht zaehlen

Voraussetzung: `wget` ist im Image vorhanden. Bei der meisten Linux-basierten Images ist das der Fall; bei `distroless`/`scratch`-basierten Images fehlt es. In diesem Fall den `test:`-Eintrag auf `curl` umstellen oder das Tool ueber ein eigenes Basis-Image nachinstallieren.

Status abfragen:

```bash
# Lokal
docker ps --filter name=dockhand  # STATUS-Spalte enthaelt "(healthy)"
docker inspect --format '{{.State.Health.Status}}' dockhand

# Swarm
docker service ps dockhand_dockhand
```

---

## Starten

### Im Swarm

```bash
cd docker-compose/dockhand
cp .env.example .env
# .env anpassen (DOCKHAND_HOST_PORT, DOCKHAND_IMAGE_TAG)
# docker-compose.yml: Traefik-Domain anpassen
docker stack deploy -c docker-compose.yml dockhand
```

### Lokal (ohne Swarm)

```bash
cd docker-compose/dockhand
cp .env.example .env
# .env anpassen
docker compose up -d
```

> Hinweis: Im Standalone-Modus wird der `deploy:`-Block ignoriert, das `proxy`-Netz muss als normales Bridge-Netz existieren (`docker network create proxy`).

---

## Verifikation nach dem ersten Start

- Container laeuft: `docker ps --filter name=dockhand` (lokal) bzw. `docker service ps dockhand_dockhand` (Swarm).
- Logs: `docker logs dockhand` bzw. `docker service logs dockhand_dockhand` — Dockhand sollte ohne Fehler starten und einen URL-Hinweis ausgeben.
- Web-UI erreichbar: `http://<host>:<DOCKHAND_HOST_PORT>` (lokal) bzw. `https://<dein-fqdn>` (ueber Traefik).
- **Default-Login verifizieren**: Falls das Image einen initialen Admin-Account voraussetzt, den Default-Login gemaess Image-Doku aendern.
- **Healthcheck pruefen**: Der Service hat einen `healthcheck:`-Block (siehe Sektion "Healthcheck"). Status mit `docker ps --filter name=dockhand` (lokal: Spalte `STATUS` zeigt `(healthy)`) bzw. `docker service ps dockhand_dockhand` (Swarm: Spalte `CURRENT STATE`) ablesen. Fuer Details: `docker inspect --format '{{.State.Health.Status}}' dockhand` (lokal) bzw. `docker inspect --format '{{.State.Health.Status}}' dockhand_dockhand.1.<task-id>` (Swarm).

## Status und Logs

```bash
# Swarm
docker service ps dockhand_dockhand
docker service logs -f dockhand_dockhand

# Lokal
docker compose ps
docker compose logs -f dockhand
```

## Stoppen

```bash
# Swarm
docker stack rm dockhand

# Lokal
docker compose down
```

## Update

1. `DOCKHAND_IMAGE_TAG` in `.env` auf die gewuenschte Version setzen (z. B. `1.2.3`).
2. Neu deployen:
   ```bash
   # Swarm
   docker stack deploy -c docker-compose.yml dockhand

   # Lokal
   docker compose pull
   docker compose up -d
   ```

## Backup

Regelmaessig `data/` sichern (Anwendungsdaten, Konfiguration, ggf. SQLite-DB):

```bash
tar -czf dockhand-backup-$(date +%F).tar.gz data/
```

## Troubleshooting

- **Service startet nicht, Fehler `network proxy not found`**: Das externe Netz `proxy` fehlt. Im Swarm: `docker network create --driver=overlay proxy`. Im Standalone-Modus: `docker network create proxy`.
- **Port `3000` (bzw. `DOCKHAND_HOST_PORT`) belegt**: anderen Host-Port in `.env` setzen und Container neu starten. Den Container-internen Port `3000` **nicht** aendern, das ist der Image-Default.
- **`proxy`-Netz fehlt beim `docker stack deploy`**: zuerst das Netz anlegen, dann erneut deployen. Siehe Sektion "Voraussetzungen".
- **Web-UI nicht erreichbar ueber `https://<fqdn>`**: Pruefen, ob Traefik den Service entdeckt (`docker service logs traefik_traefik` bzw. Traefik-Dashboard unter `:8080`). DNS-Eintrag und `certresolver=letsencrypt` checken. Direkt ueber Host-Port testen, um Traefik als Fehlerquelle auszuschliessen.
