# Build from the repo root:  docker build -f apps/server/Dockerfile .
# The server imports packages/brain, so both go in the image. Secrets come from the host, never the image.
FROM node:20-slim
WORKDIR /app
COPY packages/brain packages/brain
COPY apps/server/package.json apps/server/package-lock.json apps/server/
RUN cd apps/server && npm ci
COPY apps/server apps/server
WORKDIR /app/apps/server
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080 REQUIRE_SIGNED=1 TRUST_PROXY=1 STORE_PATH=/data/data.json HOLDBACK_HOURS=24
EXPOSE 8080
CMD ["node", "--import", "tsx", "src/index.ts"]
