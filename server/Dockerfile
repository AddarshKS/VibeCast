FROM node:24-bookworm-slim
WORKDIR /app
COPY --chown=node:node server/package.json server/package.json
COPY --chown=node:node server/src server/src
COPY --chown=node:node Sources/VibeCast/Resources/PlaylistPlan.schema.json Sources/VibeCast/Resources/PlaylistPlan.schema.json
COPY --chown=node:node Sources/VibeCast/Resources/PlaylistPlanner.txt Sources/VibeCast/Resources/PlaylistPlanner.txt
RUN mkdir -p /app/data && chown node:node /app/data
USER node
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 DATABASE_PATH=/app/data/vibecast.sqlite
EXPOSE 8787
VOLUME ["/app/data"]
CMD ["node", "server/src/server.mjs"]
