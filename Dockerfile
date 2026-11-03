# =============================================================================
# ChipLab — local-first WebGPU/WASM demo + local cloud
# Build: docker build -t chiplab:0.3.0 .
# Run:   docker run --rm -p 4173:4173 chiplab:0.3.0
# =============================================================================
FROM node:22-alpine AS runtime
WORKDIR /app

# The server has no npm dependencies; only Node built-ins.
COPY package.json ./package.json
COPY backend ./backend
COPY web ./web
COPY mcp ./mcp

ENV NODE_ENV=production \
    PORT=4173 \
    HOST=0.0.0.0 \
    CHIPLAB_DATA_DIR=/app/.data

# The local cloud writes JSON into .data; the runtime user must own it.
RUN mkdir -p /app/.data && chown -R node:node /app

EXPOSE 4173
USER node

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4173/api/health >/dev/null || exit 1

CMD ["node", "backend/server.mjs"]
