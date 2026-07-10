# docker-templates

Sammlung von Docker-Compose-Templates fuer selbstgehostete Services (Schwerpunkt: Docker Swarm + Traefik als externer Reverse-Proxy).

## Templates

| Dienst    | Pfad                       | Status     |
|-----------|----------------------------|------------|
| GitLab CE | `docker-compose/gitlab/`   | verfuegbar |
| Dockhand  | `docker-compose/dockhand/` | verfuegbar |

## Konventionen

- Sprache der Templates und READMEs ist Deutsch → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
- `docker-compose.yml` referenziert ausschliesslich `${VAR_NAME}`; Werte liegen in `.env` (nicht committen) → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
- Persistenz ueber Bind-Mounts in lokale Unterverzeichnisse (`./data`, `./logs`, ...) → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
- Traefik-Labels koennen aktiv im Compose stehen; das `proxy`-Netz ist als `external: true` deklariert → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
- Jedes Template enthaelt `docker-compose.yml`, `.env.example`, `.gitignore`, `README.md` und `data/.gitkeep` → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
- **Verbindliche Quelle fuer Stilfragen: [`.github/copilot-instructions.md`](.github/copilot-instructions.md).**

## Stack deployen (Docker Swarm)

Voraussetzung: Traefik laeuft bereits im Swarm und ist an das externe Netz `proxy` gebunden. Netz einmalig anlegen, falls noch nicht vorhanden:

```bash
docker network inspect proxy >/dev/null 2>&1 || docker network create --driver=overlay proxy
```

Pro Dienst:

```bash
# GitLab
cd docker-compose/gitlab
cp .env.example .env
# .env anpassen
docker stack deploy -c docker-compose.yml gitlab

# Dockhand
cd ../dockhand
cp .env.example .env
# .env anpassen
docker stack deploy -c docker-compose.yml dockhand
```

## Lokal mit `docker compose` starten

Jedes Template laesst sich auch ausserhalb eines Swarms starten — z. B. zum Testen auf einer Workstation. In diesem Modus gilt:

- `deploy:`-Bloecke (Replicas, Placement-Constraints, Restart-Policy) werden **ignoriert**.
- Traefik-Labels bleiben im Compose stehen, sind aber **inert**, solange kein Traefik-Daemon den Docker-Provider aktiviert hat.
- Overlay-Netze werden zu **Bridge-Netzen** heruntergestuft bzw. vom Compose-Plugin lokal aufgeloest. Externe Netze wie `proxy` muessen als normales Bridge-Netz existieren: `docker network create proxy`.

Beispiel:

```bash
cd docker-compose/dockhand
cp .env.example .env
docker compose up -d
```

## Neues Template hinzufuegen

Verzeichnis `docker-compose/<service-name>/` anlegen und die im Repo-Standard vorgegebene Struktur befuellen. Vollstaendige Schritt-fuer-Schritt-Anleitung (Pflicht-Dateien, `.env`-Konventionen, README-Pflichtinhalte, persistente Datenverzeichnisse) → Details in [`.github/copilot-instructions.md`](.github/copilot-instructions.md), Abschnitt "Adding a New Template".

## Sicherheit

- Templates, die `/var/run/docker.sock` in einen Container mounten (z. B. Dockhand, GitLab-Runner mit Docker-Executor), geben dem Container **Root-Zugriff auf den Docker-Daemon**. Solche Dienste niemals ungesichert ins Internet stellen. Hinweise pro Template stehen im jeweiligen README unter "Sicherheitshinweis: ...".
- `.env`-Dateien enthalten Credentials und Tokens und duerfen **nie** ins Repository committet werden. Jedes Template hat einen eigenen `.gitignore`, der `.env` ausschliesst. Vor dem ersten Start alle Platzhalter (`changeme`, `glrt-XXX...`, Beispiel-Domains) durch produktive Werte ersetzen.
- Beispiel-Domains (`example.com`, `example.tld`, `example.com`) im Compose und in `.env.example` dienen nur der Veranschaulichung. Vor Deploy an die eigene Domain anpassen.
