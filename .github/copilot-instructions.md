# Copilot Instructions

## Repository Overview

This is a collection of Docker Compose deployment templates for self-hosted services. Each template lives under `docker-compose/<service-name>/` and is fully self-contained.

## Architecture

Each service directory follows this pattern:

```
docker-compose/<service>/
├── Dockerfile          # Custom image build (when needed)
├── docker-compose.yml  # References ${ENV_VARS} only — no hardcoded values
├── .env                # Actual values (never commit credentials)
├── README.md           # Human-readable setup guide
└── <data-dirs>/        # Persistent volume mount points (e.g. data/, logs/, postgres/, opensearch/)
```

## Key Conventions

### Environment Variables
- `docker-compose.yml` must use `${VAR_NAME}` syntax for **all** configurable values — no hardcoded passwords, ports, or hostnames.
- The corresponding `.env` file holds the actual values.
- `.env` files contain credentials and **must not be committed**. Add a `.gitignore` or provide `.env.example` files instead.

### README Requirement
- Every template directory **must** include a `README.md`.
- The `README.md` must explain how to run the stack with Docker Compose (`build`, `up -d`, `logs`, `down`, and update flow).
- The `README.md` must document all user-defined settings required in `.env`, especially:
	- passwords/credentials that must be set,
	- exposed ports and how to change them,
	- container and service names/hostnames that can or must be configured.
- The `README.md` should include a short "first-run checklist" so a user can configure required values before startup.

### Docker Compose
- Services use `restart: unless-stopped`.
- Named volumes are **not** used — all persistent data is mounted from local subdirectories (`./postgres`, `./data`, `./opensearch`, etc.) so backups are straightforward.
- No reverse proxy is included in the compose stack — TLS termination is handled externally.
- Inter-service hostnames match the service name in `docker-compose.yml` (e.g. `DB_HOST: postgres`, `SEARCH_HOST: opensearch`).

### Dockerfiles
- Base images are pinned to a minor version (e.g. `tomcat:10.1-jre21-temurin`, `postgres:15`).
- The mailarchiva image downloads the application WAR at build time from a CDN URL stored in `ENV MAILARCHIVA_WAR_URL`.

### OpenSearch
- Runs as a single-node cluster (`discovery.type: single-node`).
- Security plugin is disabled (`plugins.security.disabled: true`) — rely on network-level access controls.

## Operational Commands

```bash
# Build and start a stack
cd docker-compose/<service>
docker compose build
docker compose up -d

# View running containers
docker ps

# View logs
docker compose logs -f <service>

# Stop stack
docker compose down

# Update (rebuild image + restart)
docker compose pull
docker compose build
docker compose up -d
```

## Backup

Back up these local directories for each stack:

- `data/` — application data
- `postgres/` — database files
- `opensearch/` — search index

## Adding a New Template

1. Create `docker-compose/<new-service>/`
2. Add `Dockerfile` (if a custom image is needed), `docker-compose.yml`, `.env`, and `README.md`
3. Follow the env-var-only convention in `docker-compose.yml`
4. Ensure `README.md` documents required passwords, ports, and naming variables for first-time setup
5. Create the empty persistent-data directories and add `.gitkeep` files so they're tracked
