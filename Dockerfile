FROM node:current-trixie-slim AS node_source

FROM ghcr.io/bsblog/python-nogil:latest AS python_source

FROM tianon/gosu:debian AS gosu_source

FROM debian:trixie-slim AS base

COPY --from=node_source /usr/local/bin/node /usr/local/bin/
COPY --from=node_source /usr/local/bin/npm /usr/local/bin/
COPY --from=node_source /usr/local/bin/npx /usr/local/bin/
COPY --from=node_source /usr/local/include/node /usr/local/include/node
COPY --from=node_source /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=python_source /usr/local/bin/python* /usr/local/bin/
COPY --from=python_source /usr/local/include/python* /usr/local/include/
COPY --from=python_source /usr/local/lib/libpython* /usr/local/lib/
COPY --from=python_source /usr/local/lib/python* /usr/local/lib/

FROM base AS build

ENV CI=true
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH="/usr/local/bin:${PNPM_HOME}:/opt/hermes/.venv/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    libffi-dev \
    procps \
    ripgrep \
    sudo \
    libatomic1 \
    && apt-get clean \
    && (apt-get dist-clean || true)

RUN npm install -g npm@latest pnpm@latest && npm cache clean --force
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
COPY --from=gosu_source /usr/local/bin/gosu /usr/local/bin/gosu

RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes

WORKDIR /opt

ARG HERMES_VERSION=main
RUN set -eux; \
    HERMES_GIT_REF="${HERMES_VERSION}"; \
    EXPECTED_SHORT_SHA=""; \
    if printf '%s' "${HERMES_VERSION}" | grep -Eq '^main-[0-9a-f]{7,}$'; then \
        HERMES_GIT_REF="main"; \
        EXPECTED_SHORT_SHA="${HERMES_VERSION#main-}"; \
        git clone --depth 1 --branch "${HERMES_GIT_REF}" --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes; \
    elif printf '%s' "${HERMES_VERSION}" | grep -Eq '^[0-9a-f]{7,40}$'; then \
        git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes; \
        git -C /opt/hermes checkout "${HERMES_VERSION}"; \
        git -C /opt/hermes submodule update --init --recursive; \
    else \
        git clone --depth 1 --branch "${HERMES_GIT_REF}" --recurse-submodules https://github.com/NousResearch/hermes-agent.git /opt/hermes; \
    fi; \
    if [ -n "${EXPECTED_SHORT_SHA}" ]; then \
        ACTUAL_SHORT_SHA="$(git -C /opt/hermes rev-parse --short=7 HEAD)"; \
        test "${ACTUAL_SHORT_SHA}" = "${EXPECTED_SHORT_SHA}"; \
    fi; \
    git -C /opt/hermes rev-parse HEAD > /opt/hermes/hermes-commit.txt

WORKDIR /opt/hermes

RUN set -eux; \
    if [ -f package-lock.json ] && [ ! -f pnpm-lock.yaml ]; then \
        pnpm import; \
    fi; \
    pnpm install --frozen-lockfile --prefer-offline; \
    pnpm prune --prod; \
    rm -rf /opt/hermes/node_modules/.cache; \
    apt-get clean; \
    (apt-get dist-clean || true)

RUN set -eux; \
    cd /opt/hermes/scripts/whatsapp-bridge; \
    if [ -f package-lock.json ] && [ ! -f pnpm-lock.yaml ]; then \
        pnpm import; \
    fi; \
    pnpm install --frozen-lockfile --prefer-offline; \
    pnpm prune --prod; \
    rm -rf /opt/hermes/scripts/whatsapp-bridge/node_modules/.cache

RUN chown -R hermes:hermes /opt/hermes

USER hermes

RUN uv venv /opt/hermes/.venv && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -e ".[all]"

FROM base AS runtime

LABEL org.opencontainers.image.source="https://github.com/BsBlog/hermes-docker"
LABEL org.opencontainers.image.title="hermes-docker"
LABEL org.opencontainers.image.description="Pre-built Hermes Agent Docker image"
LABEL org.opencontainers.image.licenses="MIT"

ENV HERMES_HOME=/opt/data
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH="/usr/local/bin:/opt/hermes/.venv/bin:${PNPM_HOME}:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    procps \
    ripgrep \
    sudo \
    libatomic1 \
    && apt-get clean \
    && (apt-get dist-clean || true)

RUN npm install -g npm@latest pnpm@latest && npm cache clean --force
COPY --from=gosu_source /usr/local/bin/gosu /usr/local/bin/gosu
COPY --from=build /opt/hermes /opt/hermes

RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes && \
    echo 'hermes ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    chmod +x /opt/hermes/docker/entrypoint.sh && \
    mkdir -p /opt/data && \
    printf '%s\n' '#!/usr/bin/env bash' 'exec /opt/hermes/.venv/bin/hermes "$@"' > /usr/local/bin/hermes && \
    chmod +x /usr/local/bin/hermes && \
    printf "%s\n" "alias hermes='/opt/hermes/.venv/bin/hermes'" > /etc/profile.d/hermes.sh && \
    chmod 0644 /etc/profile.d/hermes.sh && \
    printf "%s\n" "alias hermes='/opt/hermes/.venv/bin/hermes'" >> /etc/bash.bashrc

WORKDIR /opt/hermes

RUN pnpm exec playwright install --with-deps chromium --only-shell && \
    apt-get clean && \
    (apt-get dist-clean || true)

VOLUME ["/opt/data"]

WORKDIR /opt/data

ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["--help"]
