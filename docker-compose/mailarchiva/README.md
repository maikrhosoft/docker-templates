# MailArchiva + PostgreSQL + OpenSearch + Dovecot

Docker-Compose-Template fuer MailArchiva mit:
- MailArchiva Webanwendung
- PostgreSQL Datenbank
- OpenSearch Index
- Dovecot IMAP/IMAPS Dienst (z. B. als IMAP-Quelle fuer Imports)

## Verzeichnisstruktur

```text
mailarchiva/
├── Dockerfile
├── docker-compose.yml
├── .env
├── README.md
├── data/
├── logs/
├── postgres/
├── opensearch/
└── dovecot/
    ├── Dockerfile
    ├── entrypoint.sh
    ├── conf/
   │   ├── dovecot.conf
   │   └── certs/
    └── mail/
```

## First-Run Checkliste

1. Werte in `.env` pruefen und starke Passwoerter setzen.
2. Mindestens folgende Passwoerter aendern:
   - `DB_PASSWORD`
   - `OPENSEARCH_INITIAL_ADMIN_PASSWORD`
   - `DOVECOT_PASSWORD`
3. Ports anpassen, falls auf dem Host bereits belegt:
   - `MAILARCHIVA_PORT`
   - `DOVECOT_IMAP_PORT`
   - `DOVECOT_IMAPS_PORT`
4. Optional Container-Namen anpassen:
   - `MAILARCHIVA_CONTAINER_NAME`
   - `POSTGRES_CONTAINER_NAME`
   - `OPENSEARCH_CONTAINER_NAME`
   - `DOVECOT_CONTAINER_NAME`

## Wichtige .env Einstellungen

- `MAILARCHIVA_PORT`: Host-Port fuer MailArchiva (Container-Port 8080)
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`: PostgreSQL Verbindung
- `SEARCH_HOST`, `SEARCH_PORT`: OpenSearch Verbindung
- `OPENSEARCH_INITIAL_ADMIN_PASSWORD`: Initiales OpenSearch Admin Passwort
- `DOVECOT_IMAP_PORT`: Host-Port fuer IMAP (Container-Port 143)
- `DOVECOT_IMAPS_PORT`: Host-Port fuer IMAPS/TLS (Container-Port 993)
- `DOVECOT_USER`, `DOVECOT_PASSWORD`: IMAP Benutzer fuer Dovecot
- `DOVECOT_TLS_CN`: Common Name fuer automatisch erzeugtes TLS-Zertifikat

## Starten

```bash
cd docker-compose/mailarchiva
docker compose build
docker compose up -d
```

## Status und Logs

```bash
docker compose ps
docker compose logs -f mailarchiva
docker compose logs -f dovecot
docker compose logs -f postgres
docker compose logs -f opensearch
```

## Stoppen

```bash
docker compose down
```

## Update

```bash
docker compose pull
docker compose build
docker compose up -d
```

## Zugriff

- MailArchiva Web: `http://SERVER-IP:${MAILARCHIVA_PORT}`
- Dovecot IMAP:
  - Host: `SERVER-IP`
  - Port: `${DOVECOT_IMAP_PORT}`
  - Benutzer: Wert aus `DOVECOT_USER`
  - Passwort: Wert aus `DOVECOT_PASSWORD`
- Dovecot IMAPS (TLS):
   - Host: `SERVER-IP`
   - Port: `${DOVECOT_IMAPS_PORT}`
   - TLS: aktiv und erforderlich
   - Zertifikat: wird beim ersten Start automatisch erzeugt, wenn keines vorhanden ist

## Persistente Daten

Diese Verzeichnisse sichern:
- `data/`
- `logs/`
- `postgres/`
- `opensearch/`
- `dovecot/mail/`
- `dovecot/conf/certs/`
