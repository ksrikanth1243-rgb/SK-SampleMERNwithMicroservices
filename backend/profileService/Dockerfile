FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev --silent
COPY . .

FROM node:18-alpine
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app ./
USER appuser
EXPOSE 3002
ENV NODE_ENV=production PORT=3002
CMD ["node", "index.js"]
