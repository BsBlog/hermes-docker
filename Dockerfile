FROM node:current-trixie-slim AS node_source

RUN set -eux; \
    mkdir -p /opt/runtime/node/bin /opt/runtime/node/lib /opt/runtime/node/include /opt/runtime/node/share /opt/runtime/node/opt; \
    cp -a /usr/local/bin/node /opt/runtime/node/bin/; \
    cp -a /usr/local/lib/node_modules /opt/runtime/node/lib/; \
    cp -a /usr/local/include/node /opt/runtime/node/include/; \
    cp -a /usr/local/share/doc /opt/runtime/node/share/ || true; \
    cp -a /usr/local/share/man /opt/runtime/node/share/ || true; \
    cp -a /usr/local/bin/docker-entrypoint.sh /opt/runtime/node/bin/; \
    yarn_real="$(readlink -f /usr/local/bin/yarn)"; \
    yarn_root="$(dirname "$(dirname "$yarn_real")")"; \
    cp -a "$yarn_root" /opt/runtime/node/opt/yarn

FROM python:slim-trixie AS python_source

RUN set -eux; \
    mkdir -p /opt/runtime/python; \
    cp -a /usr/local/bin /opt/runtime/python/; \
    cp -a /usr/local/lib /opt/runtime/python/; \
    cp -a /usr/local/include /opt/runtime/python/; \
    cp -a /usr/local/share /opt/runtime/python/

FROM tianon/gosu:debian AS gosu_source

FROM debian:trixie-slim AS base

COPY --from=node_source /opt/runtime/node/bin/node /usr/local/bin/
COPY --from=node_source /opt/runtime/node/lib/node_modules /usr/local/lib/node_modules
COPY --from=node_source /opt/runtime/node/include/node /usr/local/include/node
COPY --from=node_source /opt/runtime/node/bin/docker-entrypoint.sh /usr/local/bin/
COPY --from=node_source /opt/runtime/node/opt/yarn /opt/yarn

COPY --from=python_source /opt/runtime/python/bin/python* /usr/local/bin/
COPY --from=python_source /opt/runtime/python/bin/pip* /usr/local/bin/
COPY --from=python_source /opt/runtime/python/bin/idle* /usr/local/bin/
COPY --from=python_source /opt/runtime/python/bin/pydoc* /usr/local/bin/
COPY --from=python_source /opt/runtime/python/include/python* /usr/local/include/
COPY --from=python_source /opt/runtime/python/lib/libpython* /usr/local/lib/
COPY --from=python_source /opt/runtime/python/lib/python* /usr/local/lib/

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    netbase \
    tzdata \
    libatomic1 \
    && apt-get clean \
    && (apt-get dist-clean || true)

RUN set -eux; \
    ln -sf /usr/local/bin/node /usr/local/bin/nodejs; \
    ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    ln -sf /opt/yarn/bin/yarn /usr/local/bin/yarn; \
    ln -sf /opt/yarn/bin/yarnpkg /usr/local/bin/yarnpkg; \
    [ -e /usr/local/bin/python ] || ln -sf /usr/local/bin/python3 /usr/local/bin/python; \
    [ -e /usr/local/bin/pip ] || ln -sf /usr/local/bin/pip3 /usr/local/bin/pip; \
    ldconfig
RUN npm install -g npm@latest pnpm@latest && npm cache clean --force

FROM base AS build

ENV CI=true
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH="/usr/local/bin:${PNPM_HOME}:/opt/hermes/.venv/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
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

# RUN set -eux; \
#     cd /opt/hermes/scripts/whatsapp-bridge; \
#     if [ -f package-lock.json ] && [ ! -f pnpm-lock.yaml ]; then \
#         pnpm import; \
#     fi; \
#     pnpm install --frozen-lockfile --prefer-offline; \
#     pnpm prune --prod; \
#     rm -rf /opt/hermes/scripts/whatsapp-bridge/node_modules/.cache; \
#     apt-get clean; \
#     (apt-get dist-clean || true)

RUN set -eux; \
    cd /opt/hermes/web; \
    if [ -f package-lock.json ] && [ ! -f pnpm-lock.yaml ]; then \
        pnpm import; \
    fi; \
    pnpm install --frozen-lockfile --prefer-offline; \
    pnpm run build; \
    pnpm prune --prod; \
    apt-get clean; \
    (apt-get dist-clean || true)

RUN chown -R hermes:hermes /opt/hermes

USER hermes

RUN uv venv /opt/hermes/.venv && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir --no-build-isolation-package hermes-agent ".[all]" && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir "./tinker-atropos"

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
    curl \
    ffmpeg \
    procps \
    ripgrep \
    sudo \
    && apt-get clean \
    && (apt-get dist-clean || true)

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

RUN pnpx playwright install --with-deps chromium --only-shell && \
    apt-get clean && \
    (apt-get dist-clean || true)

VOLUME ["/opt/data"]

WORKDIR /opt/data

ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["--help"]
