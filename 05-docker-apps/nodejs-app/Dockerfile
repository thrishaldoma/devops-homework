FROM node:20-alpine
WORKDIR /app
# Copy manifests first so the npm layer stays cached
# when only application source changes
COPY package*.json ./
RUN npm install --omit=dev
COPY server.js ./
EXPOSE 3000
CMD ["npm", "start"]
