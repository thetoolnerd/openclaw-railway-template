# --------------------------------------------------------------------------------
# Stage 1: Build OpenClaw from source
# --------------------------------------------------------------------------------
FROM node:22-bookworm AS openclaw-build

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git ca-certificates curl python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun for build
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable
WORKDIR /openclaw

ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch package.json files
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# --------------------------------------------------------------------------------
# Stage 2: Runtime (All Tools Included)
# --------------------------------------------------------------------------------
FROM node:22-bookworm
ENV NODE_ENV=production

# 1. Install System Dependencies & Keys for GitHub CLI
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl build-essential gcc g++ make \
    procps file git python3 pkg-config sudo wget unzip nano vim \
    gnupg \
  && rm -rf /var/lib/apt/lists/*

# 2. Install GitHub CLI (Official Debian Method)
#    We do this as root so it is available globally to all users
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# 3. Install Global NPM Tools (Vercel)
#    These will be placed in /usr/local/bin, accessible by everyone.
RUN npm install -g vercel 

# 3.1 Install Developer CLIs (Global)

# Supabase CLI
RUN curl -fsSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz \
  | tar -xz -C /usr/local/bin supabase \
  && chmod +x /usr/local/bin/supabase

# Factory CLI (official installer)
RUN curl -fsSL https://app.factory.ai/cli | sh \
  && ln -s /root/.factory/bin/factory /usr/local/bin/factory


# Firecrawl CLI
RUN npm install -g firecrawl-cli

# Convex CLI
RUN npm install -g convex


# agent-browser + Chromium (heavy)
RUN npm install -g agent-browser \
  && agent-browser install


# 4. Create 'openclaw' user with Passwordless Sudo
RUN useradd -m -s /bin/bash openclaw \
  && echo 'openclaw ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 5. Switch to user to install Homebrew (Optional backup)
#    (Even though we installed gh/node tools globally, Brew is still useful for other random tools)
USER openclaw
WORKDIR /home/openclaw

RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/openclaw/.linuxbrew/bin:/home/openclaw/.linuxbrew/sbin:${PATH}"

# 6. Final App Setup
USER root
WORKDIR /app
RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

COPY --from=openclaw-build /openclaw /openclaw

# Executable wrapper
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# Give ownership to openclaw
RUN chown -R openclaw:openclaw /app /openclaw

# 7. Start
USER openclaw
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]

# UPDATE THIS LINE:
# We use sudo to take ownership of /data before starting the server
CMD ["/bin/bash", "-c", "sudo mkdir -p /data && sudo chown -R openclaw:openclaw /data && node src/server.js"]
