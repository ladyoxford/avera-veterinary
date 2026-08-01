FROM node:20-alpine AS production
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts
COPY src ./src
COPY migrations ./migrations
COPY documentation ./documentation
COPY public ./public
COPY tests ./tests
EXPOSE 8080
CMD ["node", "src/server.js"]
