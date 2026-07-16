# Pi-hole v6 (Docker Swarm + Traefik)

Docker-Compose-Template fuer [Pi-hole](https://pi-hole.net/) v6 als DNS- und Web-Service mit Traefik-Labels und Persistenz ueber lokale Bind-Mounts.

## Was der Stack macht

- **pihole** ist ein netzwerkweiter Werbe- und Tracker-Blocker (DNS-Sinkhole). Er beantwortet DNS-Queries auf Port 53 und blockt Anfragen an bekannte Werbe-/Tracking-Domains.
- Die **Web-UI** (Port 80 im Container) ermoeglicht die Konfiguration von Blocklisten, Whitelists/Blacklists, Upstream-DNS-Servern und DHCP-Einstellungen.
- **Traefik** (externer Reverse-Proxy, nicht im Stack enthalten) liest die Labels am Service und routet HTTPS fuer `pihole.example.com` auf den Container-Port `80`.
- Persistenz erfolgt ueber `./etc-pihole` als Bind-Mount (enthaelt `gravity.db` und die Pi-hole-Konfiguration) — kein benanntes Volume, einfache Backups per `tar`/`rsync`.

---

## Verzeichnisstruktur

```text
pihole/
├── docker-compose.yml          # Base-File (standalone-tauglich)
├── docker-compose.swarm.yml    # Swarm-Override (proxy-Netz + overlay)
├── .env.example
├── .gitignore
├── README.md
├── etc-pihole/.gitkeep         # /etc/pihole (Konfiguration, gravity.db)
└── etc-dnsmasq.d/.gitkeep      # /etc/dnsmasq.d (optional, v6 nicht zwingend)
```

7 Dateien (5 Root-Dateien + 2 `.gitkeep` in den Bind-Mount-Verzeichnissen).

## Voraussetzungen

- Docker Engine (Swarm-Modus optional — nur fuer den Swarm-Pfad mit Traefik noetig: `docker swarm init` auf einem Manager-Node).
- **Port 53 (tcp+udp) auf dem Host frei** — Pi-hole bindet DNS an `0.0.0.0:53`. Auf vielen Linux-Distributionen belegt `systemd-resolved` Port 53 (siehe Troubleshooting).
- Host-Ports `8080` (HTTP) und `8443` (HTTPS) frei fuer den Direktzugriff ohne Traefik (ueber `.env` aenderbar).
- **Nur Swarm-Pfad**: Externes Overlay-Netz `proxy` existiert (`docker network create --driver=overlay proxy`). Traefik muss ebenfalls an diesem Netz haengen.
- Optional: DNS-Eintrag fuer `pihole.example.com` auf eine oeffentliche IP und Port-Forwarding 80/443 im Router.

## Netzwerk

- `pihole-internal` (Base-File: Bridge; Swarm-Override: Overlay, vom Stack angelegt): internes Netz fuer Pi-hole. Im Standalone-Modus (nur Base-File) als Bridge angelegt — funktioniert out-of-the-box ohne Swarm.
- `proxy` (Overlay, **extern**, `name: ${PROXY_NETWORK_NAME}`): gemeinsames Netz mit Traefik. **Nur im Swarm-Override** (`docker-compose.swarm.yml`) definiert; muss vor `docker stack deploy` manuell angelegt sein, sonst schlaegt das Deploy fehl. Im Standalone-Modus wird dieses Netz nicht referenziert.

---

## First-Run Checkliste

1. `cd docker-compose/pihole` und `cp .env.example .env`.
2. In `.env` das `PIHOLE_WEBPASSWORD` auf eine **lange Zufallszeichenkette** setzen (nicht `changeme` belassen).
3. In `docker-compose.swarm.yml` die Traefik-Domain anpassen: `PIHOLE_TRAEFIK_DOMAIN` in `.env` auf den eigenen FQDN setzen (siehe Sektion "Traefik-Labels"). **Gleichzeitig** dient dieser Wert dem DNS-Rebind-Whitelist-Eintrag (siehe "Sicherheitshinweis: DNS-Rebind-Schutz").
4. Sicherstellen, dass **Port 53 frei** ist: `sudo ss -lntu 'sport = :53'` — falls `systemd-resolved` aktiv: `sudo systemctl stop systemd-resolved` bzw. `DNSStubListener=no` setzen (siehe Troubleshooting).
5. Host-Ports `8080`/`8443` pruefen — bei Kollisionen in `.env` anpassen.
6. **Nur Swarm-Pfad**: Pruefen, dass das externe Netz `proxy` existiert: `docker network ls | grep proxy` — falls nicht: `docker network create --driver=overlay proxy`.
7. Stack deployen: Swarm `docker compose -f docker-compose.yml -f docker-compose.swarm.yml up -d` (oder `docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml pihole`); lokal `docker compose up -d`.

## Wichtige `.env` Einstellungen

| Variable | Default | Bedeutung |
| --- | --- | --- |
| `PIHOLE_IMAGE_TAG` | `latest` | Image-Tag von `pihole/pihole`. Fuer reproduzierbare Deploys auf einen konkreten Tag pinnen (z. B. `2026.07.2`). |
| `PIHOLE_HOST_PORT_HTTP` | `8080` | Host-Port fuer direkten Zugriff auf die Web-UI ohne Traefik. Container horcht intern auf `80`. |
| `PIHOLE_HOST_PORT_HTTPS` | `8443` | Host-Port fuer das FTL-self-signed-Zertifikat (nur ohne Traefik noetig). Container horcht intern auf `443`. |
| `PIHOLE_TZ` | `Europe/Berlin` | Zeitzone fuer den Container. |
| `PIHOLE_WEBPASSWORD` | `changeme` | Web-UI-Passwort (Pi-hole v6: `FTLCONF_webserver_api_password`). **Zwingend aendern.** |
| `PIHOLE_TRAEFIK_DOMAIN` | `pihole.example.com` | Traefik-Domain fuer den DNS-Rebind-Whitelist-Eintrag. Muss exakt der `Host(...)`-Rule im Compose entsprechen und VOR dem ersten Start konsistent gesetzt sein. |
| `PROXY_NETWORK_NAME` | `proxy` | Name des externen Traefik-Netzwerks. Nur im Swarm-Pfad relevant (`docker-compose.swarm.yml`). Muss vor `docker stack deploy` existieren. |

## Im Compose festgelegte Defaults

- Image: `pihole/pihole:${PIHOLE_IMAGE_TAG}` (Tag konfigurierbar)
- Container-Name: `pihole`
- Container-Ports: `80` (Web-UI), `443` (FTL-self-signed-cert), `53/tcp+udp` (DNS, fest an `0.0.0.0`)
- `restart: unless-stopped`
- `environment`: `TZ`, `FTLCONF_webserver_api_password` (v6 — **nicht** `WEBPASSWORD`), `FTLCONF_dns_listeningMode: "ALL"`, `FTLCONF_dns_rebind_protection: "true"`, `FTLCONF_dns_rebind_domains: ${PIHOLE_TRAEFIK_DOMAIN}`
- `volumes`: `./etc-pihole:/etc/pihole` (Bind-Mount, keine named volumes)
- `cap_add`: `NET_ADMIN` (nur fuer DHCP noetig), `SYS_TIME`, `SYS_NICE`. **Per Default ist keine Capability aktiv** — die drei Zeilen sind in `docker-compose.yml` als Kommentar-Doku-Block hinterlegt. Bei Bedarf (DHCP-Betrieb, NTP-Client, DNS-Prioritaet) in `docker-compose.yml` einkommentieren. Fuer DNS-only-Deploys bleibt der Block auskommentiert (empfohlen fuer minimal-privilegierte Deploys). Siehe Sektion "Sicherheitshinweis: Capabilities".
- `healthcheck`: `wget --spider http://localhost:80/admin/api.php?status`, `interval: 30s`, `timeout: 5s`, `retries: 3`, `start_period: 30s`. Siehe Sektion "Healthcheck".
- Traefik-Labels: `Host(`pihole.example.com`)`, Entrypoint `websecure`, `certresolver=letsencrypt`, Backend-Port `80`. **Domain anpassen** in `docker-compose.swarm.yml` (siehe Sektion "Traefik-Labels").
- `deploy:`-Block (Swarm): `replicas: 1`, `restart_policy: condition: any`. **Kein Placement-Constraint** — Pi-hole laeuft auf jedem Swarm-Node, der Port 53 frei hat. Wird im Standalone-`docker compose`-Modus ignoriert.

---

## Sicherheitshinweis: Port 53

Pi-hole bindet DNS an `0.0.0.0:53` (tcp+udp), damit LAN-Clients es als DNS-Server nutzen koennen. **Port 53 darf nicht oeffentlich exponiert werden**:

- **DNS-Reflection / Amplification-Angriffe**: Ein offener DNS-Resolver im Internet kann von Angreifern als Verstaerker fuer DDoS-Angriffe missbraucht werden (kleine Query -> grosse Response, Spoofing der Quell-IP).
- **DNS-basierte DDoS-Angriffe**: Offene Resolver ermoeglichen Cache-Poisoning und das Abfragen interner Informationen.

Empfehlungen:

- Pi-hole **nur im LAN** betreiben; Port 53 in der Firewall **nicht** nach aussen freigeben.
- Pi-hole-Web-UI **nicht oeffentlich** erreichbar machen (DNS-basierte DDoS-Gefahr ueber die Web-UI). Hinter Traefik mit Authentifizierung (z. B. `forwardAuth` mit Authelia/Authentik) betreiben.
- Falls Pi-hole als **DHCP-Server** eingesetzt wird und `NET_ADMIN` noetig ist: Alternative `network_mode: host` in Erwaegung ziehen, damit Pi-hole direkt auf dem Host-Interface lauscht (DHCP benoetigt Broadcasts, die im Bridge-Modus nicht weitergereicht werden).

## Sicherheitshinweis: DNS-Rebind-Schutz

Pi-hole v6 aktiviert per Default den **DNS-Rebind-Schutz** (`FTLCONF_dns_rebind_protection: "true"`). Dieser verhindert, dass private IP-Adressen in oeffentlichen DNS-Antworten aufgeloest werden (Schutz gegen Rebinding-Angriffe). Da die Traefik-Domain aber auf eine private IP routet, wuerde Pi-hole ohne Whitelist die Aufloesung der eigenen Domain blocken.

Daher wird die Traefik-Domain ueber `FTLCONF_dns_rebind_domains: ${PIHOLE_TRAEFIK_DOMAIN}` whitelistet. **Wichtig**:

- `PIHOLE_TRAEFIK_DOMAIN` in `.env` muss **exakt** der Domain entsprechen, die im Compose als `traefik.http.routers.pihole.rule=Host(...)` hinterlegt ist. Beide Werte muessen VOR dem ersten Start konsistent gesetzt sein.
- Der DNS-Rebind-Schutz bleibt aktiv — nur die konfigurierte Domain wird durchgelassen.
- Falls nach dem Setup-Wizard weitere Domains whitelistet werden sollen (z. B. weitere Services hinter demselben Traefik), muss der Schutz in der Web-UI unter *Settings -> DNS -> Advanced DNS settings* erneut konfiguriert werden, da Aenderungen an `FTLCONF_dns_rebind_domains` nur beim ersten Start greifen.

## Sicherheitshinweis: Capabilities

**Default-Konfiguration ist capability-arm**. Fuer reine DNS-only-Deploys laeuft Pi-hole ohne `cap_add` — FTL laeuft als unprivilegierter Prozess. Die drei potenziell noetigen Capabilities sind in `docker-compose.yml` per Default **auskommentiert**:

- `NET_ADMIN` — nur bei DHCP-Betrieb aktivieren (Pi-hole als DHCP-Server). Steht in `.env` unter `PIHOLE_ENABLE_DHCP=true` (Dokumentationsschalter; das eigentliche Einkommentieren erfolgt in `docker-compose.yml`).
- `SYS_TIME` — nur bei Einsatz als NTP-Client. Steht in `.env` unter `PIHOLE_ENABLE_NTP=true`.
- `SYS_NICE` — optional, fuer hoehere Prioritaet der DNS-Aufloesung (harmlos, aber nicht noetig).

Zusaetzlich ist `security_opt: ["no-new-privileges:true"]` gesetzt, damit Prozesse im Container ueber SUID-Bits oder `setcap` keine weiteren Privilegien erlangen koennen (Defense-in-Depth). Das haelt den Container-Attack-Surface minimal.

## Traefik-Labels

Die Traefik-Labels sind **ausschliesslich im Swarm-Override** (`docker-compose.swarm.yml`) hinterlegt — das Base-File `docker-compose.yml` enthaelt keine Traefik-Labels. Grund: eine standalone laufende `docker compose up -d` ohne Traefik darf die Labels nicht mitziehen, damit eine echte Traefik-Instanz auf dem Host sie nicht versehentlich mitliest. Im Swarm-Pfad werden die Labels additiv zum Base-File geladen.

Vor dem Deploy anpassen:

- `traefik.http.routers.pihole.rule=Host(`${PIHOLE_TRAEFIK_DOMAIN}`)` — Domain ueber `PIHOLE_TRAEFIK_DOMAIN` in `.env` setzen.
- Pruefen, dass `entrypoints=websecure` und `certresolver=letsencrypt` zu den in Traefik konfigurierten Entrypoints/Certresolvern passen.
- `traefik.docker.network=${PROXY_NETWORK_NAME}` ist noetig, weil der Container an **mehreren** Netzen haengt. Traefik muss wissen, ueber welches Netz es den Container erreicht. Der Netzname wird ueber `PROXY_NETWORK_NAME` in `.env` konfiguriert (Default `proxy`).

Workaround ohne Traefik: ueber den Host-Port `http://<host>:<PIHOLE_HOST_PORT_HTTP>` direkt auf die Web-UI zugreifen (z. B. im LAN ohne TLS).

---

## Healthcheck

Der Service hat einen `healthcheck:`-Block in `docker-compose.yml`, der die Web-UI ueber `wget --spider http://localhost:80/admin/api.php?status` prueft. Der `status`-Endpoint liefert ohne Authentifizierung JSON und ist stabiler als `/admin/login.html`. Standard-Parameter:

- `interval: 30s` — Pruef-Intervall
- `timeout: 5s` — Timeout pro Pruefung
- `retries: 3` — Anzahl Fehlversuche, bis der Container als `unhealthy` gilt
- `start_period: 30s` — Karenzzeit nach Container-Start, in der Fehler nicht zaehlen

Voraussetzung: `wget` ist im Image vorhanden. Bei `pihole/pihole` ist das der Fall; bei `distroless`/`scratch`-basierten Images fehlt es. In diesem Fall den `test:`-Eintrag auf `curl` umstellen oder das Tool ueber ein eigenes Basis-Image nachinstallieren.

Status abfragen:

```bash
# Lokal
docker ps --filter name=pihole  # STATUS-Spalte enthaelt "(healthy)"
docker inspect --format '{{.State.Health.Status}}' pihole

# Swarm
docker service ps pihole_pihole
```

---

## Starten

### Build

Pi-hole verwendet das offizielle Image `pihole/pihole:${PIHOLE_IMAGE_TAG}` — es gibt **kein Custom-Dockerfile** in diesem Template. `docker compose build` ist daher ein No-op und pullt per Default das Image. Der Build-Schritt kann uebersprungen werden; stattdessen direkt `docker compose pull` verwenden, um das Image vorab zu laden. Der Update-Flow ist in der Sektion "Update" beschrieben.

### Im Swarm (mit Traefik)

```bash
cd docker-compose/pihole
cp .env.example .env
# .env anpassen (PIHOLE_WEBPASSWORD, PIHOLE_IMAGE_TAG, PIHOLE_TRAEFIK_DOMAIN)
# docker-compose.swarm.yml: Traefik-Labels pruefen (Host()-Rule via PIHOLE_TRAEFIK_DOMAIN)
# PROXY_NETWORK_NAME=proxy setzen und externes Netz anlegen:
#   docker network create --driver=overlay proxy
docker compose -f docker-compose.yml -f docker-compose.swarm.yml up -d
# Alternativ Swarm-Stack:
# docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml pihole
```

### Lokal (ohne Swarm)

```bash
cd docker-compose/pihole
cp .env.example .env
# .env anpassen
docker compose up -d
```

> Hinweis: Im Standalone-Modus (nur Base-File) wird der `deploy:`-Block ignoriert und das `proxy`-Netz nicht referenziert — es ist kein externes Netz noetig. Das Netz `pihole-internal` wird im Standalone-Modus als Bridge angelegt; nur Container im selben Compose-File koennen es nutzen. Fuer externe Sidecars das interne Netz vorab erstellen (`docker network create pihole-internal`). Web-UI direkt via `http://localhost:${PIHOLE_HOST_PORT_HTTP}`.

---

## Verifikation nach dem ersten Start

- Container laeuft: `docker ps --filter name=pihole` (lokal) bzw. `docker service ps pihole_pihole` (Swarm).
- Logs: `docker logs pihole` bzw. `docker service logs pihole_pihole` — Pi-hole sollte ohne Fehler starten und einen Hinweis auf die Web-UI ausgeben.
- **DNS-Test**: `dig @<host> -p 53 google.com` (von einem anderen Host im LAN) sollte eine Antwort mit der Pi-hole-IP als Resolver liefern.
- **DNS-Smoke-Test (lokal)**: `dig @127.0.0.1 -p 53 pi.hole` sollte eine Antwort mit der Pi-hole-IP liefern (prueft, dass der Resolver auf 53 lauscht und `pi.hole` aufloest).
- Web-UI erreichbar: `http://<host>:<PIHOLE_HOST_PORT_HTTP>/admin` (lokal) bzw. `https://<dein-fqdn>/admin` (ueber Traefik).
- **Web-UI-Login**: Mit `PIHOLE_WEBPASSWORD` aus `.env` einloggen.
- **Default-Passwort aendern**: Falls der Setup-Wizard ein Default-Passwort vorschlaegt, dieses nach erstem Login in den Einstellungen aendern.
- **Upstream-DNS-Server setzen**: In der Web-UI unter *Settings -> DNS* die Upstream-DNS-Server konfigurieren (z. B. `1.1.1.1`, `8.8.8.8`), falls nicht schon geschehen.
- **Healthcheck pruefen**: Status mit `docker ps --filter name=pihole` (lokal: Spalte `STATUS` zeigt `(healthy)`) bzw. `docker service ps pihole_pihole` (Swarm: Spalte `CURRENT STATE`) ablesen. Fuer Details: `docker inspect --format '{{.State.Health.Status}}' pihole` (lokal) bzw. `docker inspect --format '{{.State.Health.Status}}' pihole_pihole.1.<task-id>` (Swarm).

## Status und Logs

```bash
# Swarm
docker service ps pihole_pihole
docker service logs -f pihole_pihole

# Lokal
docker compose ps
docker compose logs -f pihole
```

## Stoppen

```bash
# Swarm
docker stack rm pihole
# oder (compose):
# docker compose -f docker-compose.yml -f docker-compose.swarm.yml down

# Lokal
docker compose down
```

## Update

1. `PIHOLE_IMAGE_TAG` in `.env` auf die gewuenschte Version setzen (z. B. `2026.07.2`).
2. Neu deployen:
   ```bash
   # Swarm
   docker compose -f docker-compose.yml -f docker-compose.swarm.yml pull
   docker compose -f docker-compose.yml -f docker-compose.swarm.yml up -d
   # Alternativ:
   # docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml pihole

   # Lokal
   docker compose pull
   docker compose up -d
   ```

## Backup

Regelmaessig `etc-pihole/` sichern (enthaelt `gravity.db` mit allen Blocklisten, Whitelists und DNS-Einstellungen):

```bash
tar -czf pihole-backup-$(date +%F).tar.gz etc-pihole/
```

Optional zusaetzlich `etc-dnsmasq.d/` sichern, falls eigene dnsmasq-Konfigurationen abgelegt wurden (v6 nicht zwingend).

## Troubleshooting

- **`network proxy not found`**: Das externe Netz `proxy` fehlt. Nur im Swarm-Pfad relevant — im Standalone-Modus wird `proxy` nicht referenziert. Im Swarm: `docker network create --driver=overlay proxy`.
- **`bind: address already in use` auf Port 53**: Meist belegt `systemd-resolved` den Port. Loesung: `sudo systemctl stop systemd-resolved` und in `/etc/systemd/resolved.conf` den Eintrag `DNSStubListener=no` setzen, dann `sudo systemctl restart systemd-resolved`. Alternativ Pi-hole auf `127.0.0.1:53` beschraenken (verliert aber LAN-Nutzbarkeit).
- **Web-UI nicht erreichbar**: Traefik pruefen (`docker service logs traefik_traefik` bzw. Traefik-Dashboard unter `:8080`). DNS-Eintrag und `certresolver=letsencrypt` checken. Direkt ueber Host-Port `http://<host>:<PIHOLE_HOST_PORT_HTTP>/admin` testen, um Traefik als Fehlerquelle auszuschliessen. Falls der Browser DNS-Loopback aktiv hat (Pi-hole als DNS fuer den Host, auf dem Pi-hole laeuft), DNS-Loopback im Browser deaktivieren.
- **DNS-Queries gehen nicht durch**: Container-Network-Mode pruefen — Pi-hole muss an `0.0.0.0:53` lauschen (`FTLCONF_dns_listeningMode=ALL`). Firewall-Regeln fuer Port 53 pruefen. Sicherstellen, dass **kein Pi-hole-Container** auf dem Router als DNS-Server eingetragen ist, der selbst wiederum Pi-hole als Upstream nutzt (DNS-Loop).
- **FTL startet nicht**: Logs pruefen (`docker logs pihole`). `cap_add` (`NET_ADMIN`, `SYS_TIME`, `SYS_NICE`) ist per Default **nicht** gesetzt — bei Bedarf (DHCP, NTP-Client) in `docker-compose.yml` einkommentieren (siehe Sektion "Sicherheitshinweis: Capabilities"). Bei DHCP-Betrieb ggf. `network_mode: host` verwenden.

## Optionaler dnsmasq.d-Mount (fuer Power-User)

In Pi-hole v6 ist ein eigener `etc-dnsmasq.d`-Mount **nicht mehr zwingend** noetig. Fuer Power-User, die eigene dnsmasq-Konfigurationsdateien einbinden wollen (z. B. fuer `address=/domain/1.2.3.4`-Overrides), kann der Mount manuell in `docker-compose.yml` ergaenzt werden:

```yaml
    volumes:
      - ./etc-pihole:/etc/pihole
      - ./etc-dnsmasq.d:/etc/dnsmasq.d   # optional, v6 nicht zwingend
```

Das Verzeichnis `etc-dnsmasq.d/` (mit `.gitkeep`) ist bereits angelegt. Fuer eine **v5->v6-Migration** kann der Mount temporaer hilfreich sein, um alte dnsmasq-Konfigurationen zu uebernehmen.
