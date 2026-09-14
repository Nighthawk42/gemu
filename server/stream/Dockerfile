FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY broker.mjs ./
USER node
EXPOSE 8090
CMD ["node", "broker.mjs"]
