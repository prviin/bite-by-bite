FROM node:24-bookworm-slim
ENV NODE_ENV=production HOST=127.0.0.1 PORT=3000
WORKDIR /app
COPY --chown=node:node package.json server.mjs accounts.mjs chatgpt.mjs ./
COPY --chown=node:node public ./public
COPY --chown=node:node scripts ./scripts
RUN mkdir -p /app/data /backups && chown node:node /app/data /backups
USER node
CMD ["node", "server.mjs"]
