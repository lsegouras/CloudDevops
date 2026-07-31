# ---- deps ----
# Instala TODAS as deps (inclui dev) para poder buildar. Camada separada = melhor cache.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- build ----
FROM node:22-alpine AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# ---- runtime ----
# next.config.mjs usa output: 'standalone', então o build gera .next/standalone
# (server.js + node_modules mínimo). A imagem final não precisa do SDK nem das devDependencies.
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
# Next standalone escuta em 0.0.0.0:3000 dentro do container
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

# Copia só o necessário do standalone, com dono não-root:
#  - server.js + node_modules mínimo (.next/standalone)
#  - assets estáticos (.next/static) e arquivos públicos (public), que o standalone não inclui
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
COPY --from=build --chown=node:node /app/public ./public

# usuário não-root pré-existente na imagem oficial node
USER node
EXPOSE 3000

# A app expõe GET /api/health -> { status: "healthy" }. curl não existe no node:alpine,
# então o healthcheck usa o http nativo do próprio Node.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3000/api/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
