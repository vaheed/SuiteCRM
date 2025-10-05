# suitecrm-docker
LinuxServer-style multi-variant Docker repository for SuiteCRM (LTS & latest)

## What you get
- Multi-variant Dockerfiles for SuiteCRM (PHP 8.1 for SuiteCRM 8.x, PHP 7.4 for SuiteCRM 7.12 LTS)
- `docker-entrypoint.sh` that auto-downloads SuiteCRM on first run
- Migration helper `scripts/migrate_from_bitnami.sh`
- GitHub Actions workflow to build & publish images to GHCR and create releases on tag
- Example `docker-compose.yml` and `.env.example`

## Quick start (local)
1. Copy `.env.example` to `.env` and edit credentials.
2. `docker compose up -d --build`
3. If container downloads SuiteCRM on first run, wait until web is ready and visit `http://localhost:8080`.

## GitHub Actions
- The workflow `build-and-publish.yml` builds images for matrix of SuiteCRM versions and PHP variants.
- To publish to GHCR/DockerHub, add repository secrets:
  - `CR_PAT` (Personal access token with `write:packages` and `repo` if publishing to GHCR)
  - `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (if you enable DockerHub push)
- Tagging strategy:
  - Push `v8.x.y` to create an 8.x release (latest)
  - Push `v7.12.z` to create an LTS release (7.12)
