# OpenClaw Docker Image

Pre-built Docker image for [OpenClaw](https://github.com/openclaw/openclaw). This repository builds a multi-architecture image from the upstream OpenClaw source and publishes it through GitHub Actions.

## Manual Usage

### Pull the image

```bash
docker pull ghcr.io/bsblog/openclaw-docker:latest
```

### Show CLI help

```bash
docker run --rm ghcr.io/bsblog/openclaw-docker:latest --help
```

### Start the gateway

```bash
docker run -d \
  --name openclaw-gateway \
  --restart unless-stopped \
  -v ~/.openclaw:/home/node/.openclaw \
  -v ~/.openclaw/workspace:/home/node/.openclaw/workspace \
  -p 18789:18789 \
  -p 18790:18790 \
  -e OPENCLAW_SKIP_SERVICE_CHECK=true \
  ghcr.io/bsblog/openclaw-docker:latest gateway
```

## Docker Compose

```bash
git clone https://github.com/bsblog/openclaw-docker.git
cd openclaw-docker

docker compose up -d
```

## Paths and Ports

- Host config directory: `~/.openclaw`
- Host workspace directory: `~/.openclaw/workspace`
- Compose host config directory: `/opt/openclaw`
- Compose host workspace directory: `/opt/openclaw/workspace`
- Container config directory: `/home/node/.openclaw`
- Container workspace directory: `/home/node/.openclaw/workspace`
- Gateway/API port: `18789`
- Dashboard port: `18790`

## Build Automation

- The image build workflow accepts `openclaw_version`.
- The release tracker stores the last built upstream ref in `.last-openclaw-version`.
- Published manifest tags are `latest` and the Git commit SHA of this repository.
- GitHub Actions build and publish the `ghcr.io/bsblog/openclaw-docker` image.

## Links

- Upstream OpenClaw: https://github.com/openclaw/openclaw
- This Docker repository: https://github.com/bsblog/openclaw-docker
