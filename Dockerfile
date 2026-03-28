FROM node:current-trixie-slim AS base

RUN npm install -g npm@latest pnpm@latest

FROM base AS build

ENV CI=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    unzip \
    build-essential \
    procps \
    file \
    sudo \
    jq \
    && apt-get dist-clean

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN groupadd -f linuxbrew && \
    useradd -m -s /bin/bash -g linuxbrew linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    mkdir -p /home/linuxbrew/.linuxbrew && \
    chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew
    
RUN mkdir -p /home/linuxbrew/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew && \
    mkdir -p /home/linuxbrew/.linuxbrew/bin && \
    ln -s /home/linuxbrew/.linuxbrew/Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew && \
    chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew && \
    chmod -R g+rwX /home/linuxbrew/.linuxbrew

WORKDIR /app

ARG OPENCLAW_VERSION=main
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} https://github.com/openclaw/openclaw.git . && \
    echo "Building OpenClaw from branch: ${OPENCLAW_VERSION}" && \
    git rev-parse HEAD > /app/openclaw-commit.txt

RUN pnpm install --frozen-lockfile
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
RUN npm_config_script_shell=bash pnpm ui:install
RUN npm_config_script_shell=bash pnpm ui:build

RUN pnpm prune --prod \
    && rm -rf .git node_modules/.cache

FROM base AS runtime

LABEL org.opencontainers.image.source="https://github.com/BsBlog/openclaw-docker"
LABEL org.opencontainers.image.description="Pre-built OpenClaw (Clawbot) Docker image"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    sudo \
    && apt-get dist-clean

RUN groupadd -f linuxbrew \
    && useradd -m -s /bin/bash -g linuxbrew linuxbrew \
    && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY --chown=linuxbrew:linuxbrew --from=build /home/linuxbrew/.linuxbrew/ /home/linuxbrew/.linuxbrew/

WORKDIR /app

COPY --chown=node:node --from=build /app/ /app/

RUN mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace \
    && chown -R node:node /home/node \
    && chmod -R 755 /home/node/.openclaw \
    && usermod -aG linuxbrew node \
    && echo 'node ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && chmod -R g+w /home/linuxbrew/.linuxbrew

RUN pnpm dlx -y playwright@latest install-deps chromium

RUN mkdir -p /usr/local/share/ca-certificates && \
    cp /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates/ca-certificates.crt && \
    chmod 755 /usr/local/share/ca-certificates && \
    chmod 644 /usr/local/share/ca-certificates/ca-certificates.crt

RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /app/dist/index.js "$@"' > /usr/local/bin/openclaw && \
    chmod +x /usr/local/bin/openclaw && \
    printf "%s\n" "alias openclaw='node /app/dist/index.js'" >> /etc/bash.bashrc && \
    printf "%s\n" "alias openclaw='node /app/dist/index.js'" >> /home/node/.bashrc

USER node

RUN NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/ca-certificates.crt pnpm dlx -y playwright@latest install chromium

WORKDIR /home/node

ENV NODE_ENV=production
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/app/node_modules/.bin:${PATH}"

ENTRYPOINT ["openclaw"]
CMD ["--help"]