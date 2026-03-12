# Mailpiler Nutzung

## Voraussetzungen
- Docker + Compose Plugin installiert
- Externes Docker-Netzwerk `mvl` existiert
- NPM (Nginx Proxy Manager) laeuft im gleichen Netzwerk oder kann die `PILER_IPV4` erreichen

## 1) Konfiguration
Datei: `/docker/mailpiler/.env`

Wichtige Variablen:
- `PILER_HOSTNAME`: FQDN fuer den Webzugriff (z. B. `archive.example.tld`)
- `MYSQL_PASSWORD`: sicheres Passwort setzen
- `PILER_IPV4`: statische IP im `mvl`-Netz
- `PILER_VERSION`: Mailpiler-Imageversion

## 2) Starten
```bash
docker compose -f /docker/mailpiler/docker-compose.yml pull
docker compose -f /docker/mailpiler/docker-compose.yml up -d
```

## 3) Status pruefen
```bash
docker compose -f /docker/mailpiler/docker-compose.yml ps
docker logs mailpiler --tail 100
docker logs mailpiler-mysql --tail 100
docker logs mailpiler-manticore --tail 100
```

## 4) Stoppen / Neustarten
```bash
docker compose -f /docker/mailpiler/docker-compose.yml stop
docker compose -f /docker/mailpiler/docker-compose.yml start
docker compose -f /docker/mailpiler/docker-compose.yml restart
```

## 5) Update
```bash
docker compose -f /docker/mailpiler/docker-compose.yml pull
docker compose -f /docker/mailpiler/docker-compose.yml up -d
```

## 6) Reverse Proxy (NPM)
- Proxy Host auf `PILER_HOSTNAME` anlegen
- Forward Host: `mailpiler` (Containername) oder `PILER_IPV4`
- Forward Port: `80`
- SSL-Zertifikat aktivieren

## 7) Optional: SMTP-Ingest von extern
In `/docker/mailpiler/docker-compose.yml` im Service `piler` folgendes einkommentieren:
```yaml
ports:
  - "25:25"
```
Dann Stack neu starten:
```bash
docker compose -f /docker/mailpiler/docker-compose.yml up -d
```

## 8) Fehlerbehebung
1. `network mvl not found`:
```bash
docker network create mvl
```
2. `address already in use` bei `PILER_IPV4`: andere freie IP in `.env` setzen.
3. Startfehler DB/Auth: `MYSQL_PASSWORD` in `.env` und Container-Logs pruefen.
4. Web nicht erreichbar: NPM Zielhost/Port und DNS auf `PILER_HOSTNAME` kontrollieren.
