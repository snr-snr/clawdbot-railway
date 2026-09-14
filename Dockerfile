# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:24.21.0-bookworm AS openclaw-build

# Dependencies needed for openclaw build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known-good ref (tag/branch). This is the SOURCE OF TRUTH for the OpenClaw version
# (the Railway OPENCLAW_GIT_REF variable override was removed 2026-08-05). Bump via PR + merge.
# Using a released tag avoids build breakage when `main` temporarily references unpublished packages.
ARG OPENCLAW_GIT_REF=v2026.8.1
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:24.21.0-bookworm
ENV NODE_ENV=production

# Runtime system layer — declarative, persistent across deploys.
# Anything not in this list WILL be wiped on the next deploy.
# Grouped by purpose:
#   - Core/PID 1:           ca-certificates tini curl wget git
#   - Python for MCP:       python3 python3-venv python3-dev python3-pip
#   - Bootstrap reconciler: jq
#   - Skill tooling:        ripgrep ffmpeg zip unzip bzip2 xz-utils poppler-utils imagemagick libmagickwand-dev
#   - Native compile:       build-essential pkg-config libssl-dev libsqlite3-dev libpq-dev libffi-dev libyaml-dev
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates tini curl wget git \
    python3 python3-venv python3-dev python3-pip \
    jq \
    ripgrep ffmpeg zip unzip bzip2 xz-utils \
    poppler-utils imagemagick libmagickwand-dev \
    build-essential pkg-config \
    libssl-dev libsqlite3-dev libpq-dev libffi-dev libyaml-dev \
  && rm -rf /var/lib/apt/lists/*

# `openclaw update` expects pnpm. Provide it in the runtime image.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Persist user-installed tools by default by targeting the Railway volume.
# - npm global installs -> /data/npm
# - pnpm global installs -> /data/pnpm (binaries) + /data/pnpm-store (store)
ENV NPM_CONFIG_PREFIX=/data/npm
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store
ENV PATH="/data/.openclaw/bin:/data/npm/bin:/data/pnpm:${PATH}"

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide an openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# Manifest-driven bootstrap: reconciles wrappers/symlinks on every container start.
# See bootstrap.sh and manifest.json for the source of truth.
COPY manifest.json /app/manifest.json
COPY bootstrap.sh /usr/local/bin/openclaw-bootstrap
RUN chmod +x /usr/local/bin/openclaw-bootstrap

# Runtime payloads baked into the image so bootstrap can restore them onto /data
# on every boot. This is what makes the Shopify and Granola layers survive a
# redeploy, an OpenClaw upgrade that rewrites workspaces, or a lost volume.
# Secrets are NEVER baked in — tokens live only under
# /data/.openclaw/credentials/<name>/ (or Railway variables).
# See manifest.json -> provisioned.
COPY payloads /app/payloads
RUN chmod +x /app/payloads/*/bin/*

# 1Password CLI — lets bootstrap resolve secrets from a service-account vault at
# boot instead of keeping them in plaintext on /data. Needs >= 2.18 for service
# accounts. Inert unless OP_SERVICE_ACCOUNT_TOKEN is set (see manifest.secrets).
ARG OP_CLI_VERSION=2.31.1
RUN curl -sSfLo /tmp/op.zip \
      "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_CLI_VERSION}/op_linux_amd64_v${OP_CLI_VERSION}.zip" \
  && unzip -o /tmp/op.zip op -d /usr/local/bin \
  && chmod +x /usr/local/bin/op \
  && rm -f /tmp/op.zip \
  && op --version

# The wrapper listens on $PORT.
# IMPORTANT: Do not set a default PORT here.
# Railway injects PORT at runtime and routes traffic to that port.
# If we force a different port, deployments can come up but the domain will route elsewhere.
EXPOSE 8080

# Ensure PID 1 reaps zombies and forwards signals.
# Chain: tini (PID 1) -> openclaw-bootstrap (reconcile, then exec) -> app
ENTRYPOINT ["tini", "--", "/usr/local/bin/openclaw-bootstrap"]
CMD ["node", "src/server.js"]
