# Hermes Docker Image

Pre-built Docker image for [Hermes Agent](https://github.com/NousResearch/hermes-agent). This repository builds a multi-architecture image from the upstream Hermes source and publishes it through GitHub Actions.

## Manual Usage

### Pull the image

```bash
docker pull ghcr.io/bsblog/hermes-docker:latest
```

### Show CLI help

```bash
docker run --rm ghcr.io/bsblog/hermes-docker:latest --help
```

### Check the installed version

```bash
docker run --rm ghcr.io/bsblog/hermes-docker:latest version
```

### Start the gateway and API server

```bash
docker run -d \
  --name hermes-gateway \
  --restart unless-stopped \
  -v ~/.hermes:/opt/data \
  -p 8642:8642 \
  -e API_SERVER_ENABLED=true \
  -e API_SERVER_HOST=0.0.0.0 \
  -e API_SERVER_PORT=8642 \
  -e API_SERVER_KEY=change-me-local-dev \
  ghcr.io/bsblog/hermes-docker:latest gateway
```

### Run diagnostics

```bash
docker run --rm -it \
  -v ~/.hermes:/opt/data \
  ghcr.io/bsblog/hermes-docker:latest doctor
```

## Docker Compose

```bash
git clone https://github.com/bsblog/openclaw-docker.git
cd openclaw-docker

docker compose up -d hermes-gateway
docker compose run --rm hermes-cli --help
```

Compose defaults:

- Host data directory: `/opt/hermes`
- Container data directory: `/opt/data`
- Container workspace directory: `/opt/data/workspace`
- API server port: `8642`

Before exposing the API server on a real network, set a strong `API_SERVER_KEY` and narrow `API_SERVER_CORS_ORIGINS` in `/opt/hermes/.env` or via Compose environment variables.

## Container Behavior

- The image keeps a multi-stage build based on `debian:latest-slim`.
- `hermes` is available both as a command and as a shell alias.
- The runtime user is `hermes`, and that user has passwordless `sudo`.
- Node-side package installation uses `pnpm`.
- Persistent Hermes data lives under `/opt/data`.

## Build Automation

- The image build workflow accepts `hermes_version`.
- The release tracker stores the last built upstream ref in `.last-hermes-version`.
- Published manifest tags are `latest` and this repository's Git commit SHA.
- GitHub Actions build and publish the `ghcr.io/bsblog/hermes-docker` image.

## Links

- Upstream Hermes Agent: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
- This Docker repository: [bsblog/openclaw-docker](https://github.com/bsblog/openclaw-docker)
