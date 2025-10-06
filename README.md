# SuiteCRM-docker

**Multi-variant Docker images for SuiteCRM (LTS and latest versions)**
Supports PHP 7.4 (LTS) and PHP 8.1 (latest), with all required PHP extensions for SuiteCRM.

---

## Features

* Official SuiteCRM LTS (7.12.x / 7.14.x) and latest (8.x) versions
* Pre-installed PHP extensions: `gd`, `mysqli`, `pdo`, `pdo_mysql`, `zip`, `intl`, `mbstring`, `opcache`, `xml`, `soap`
* Apache + mod_rewrite ready
* Automatic download of SuiteCRM from official site or GitHub archive
* Multi-architecture builds via GitHub Actions
* Supports GHCR publishing and optional Docker Hub
* Robust entrypoint handles empty `/var/www/html` directories and preserves dotfiles

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Environment Variables](#environment-variables)
3. [Building Images](#building-images)
4. [Running the Container](#running-the-container)
5. [GitHub Actions / CI/CD](#github-actions--cicd)
6. [Troubleshooting](#troubleshooting)
7. [Migrating from Bitnami Images](#migrating-from-bitnami-images)
8. [Contributing](#contributing)
9. [License](#license)

---

## Quick Start

### Clone the repository

```bash
git clone https://github.com/vaheed/suitcrm.git
cd suitcrm
```

### Build and run with Docker Compose (example)

```yaml
# docker-compose.yml
version: "3.9"

services:
  suitecrm:
    build:
      context: .
      dockerfile: variants/php8.1-apache/Dockerfile
      args:
        SUITECRM_VERSION: latest
    ports:
      - "8080:80"
    volumes:
      - ./data/html:/var/www/html
    environment:
      - SUITECRM_VERSION=latest
    restart: unless-stopped
```

Then:

```bash
docker compose up -d --build
```

Open [http://localhost:8080](http://localhost:8080) in your browser.

---

## Environment Variables

| Variable           | Default  | Description                                                                    |
| ------------------ | -------- | ------------------------------------------------------------------------------ |
| `SUITECRM_VERSION` | `latest` | Version of SuiteCRM to install (supports `7.12.7`, `7.14.7`, `latest`, or 8.x) |
| `SUITECRM_URL`     | none     | Optional full URL to a SuiteCRM zip file; overrides `SUITECRM_VERSION`         |

---

## Building Images

### Build PHP 8.1 (latest)

```bash
docker build --progress=plain -f variants/php8.1-apache/Dockerfile -t suitecrm:latest-php8.1 .
```

### Build PHP 7.4 (LTS)

```bash
docker build --progress=plain -f variants/php7.4-apache/Dockerfile -t suitecrm:lts-php7.4 .
```

---

## Running the Container

```bash
docker run -d -p 8080:80 \
  -e SUITECRM_VERSION=latest \
  -v $(pwd)/data/html:/var/www/html \
  suitecrm:latest-php8.1
```

Check logs:

```bash
docker logs -f <container_id>
```

---

## GitHub Actions / CI/CD

* Workflow builds images for PHP 7.4 and PHP 8.1
* Pushes to GitHub Container Registry (GHCR) using `GITHUB_TOKEN`
* Optional Docker Hub push if secrets are configured

Workflow file: `.github/workflows/build-and-publish.yml`

---

## Troubleshooting

* **`mbstring` compile fails:** Ensure `libonig-dev` is installed in Dockerfile
* **`intl` compile fails:** Ensure `libicu-dev` and `pkg-config` installed
* **Login action fails:** Use `GITHUB_TOKEN` with `packages: write` permissions
* **Empty web root:** EntryPoint automatically downloads SuiteCRM if `/var/www/html` is empty; check `SUITECRM_URL` if needed

---

## Migrating from Bitnami Images

1. Backup your current Bitnami SuiteCRM volumes
2. Map volumes to `/var/www/html` in the new container
3. Ensure ownership: `chown -R www-data:www-data ./data/html`
4. Start the container and run SuiteCRM upgrade if needed

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Commit your changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/my-change`
5. Open a Pull Request

---

## License

MIT License © vaheed
