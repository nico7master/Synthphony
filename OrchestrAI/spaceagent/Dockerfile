FROM node:20-slim

# Install git, curl, ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends     git     curl     ca-certificates     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone space-agent repo (v0.66)
RUN git clone --depth 1 --branch v0.66 https://github.com/agent0ai/space-agent.git .

# Install dependencies
RUN npm install --omit=dev

# Create data directories
RUN mkdir -p /srv/space/customware /app/config

# Default environment
ENV CUSTOMWARE_PATH=/srv/space/customware
ENV HOST=0.0.0.0
ENV PORT=3000

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3     CMD curl --fail --silent http://localhost:3000/ >/dev/null 2>&1 || exit 1

# Start the server
CMD ["node", "space", "serve", "HOST=0.0.0.0", "PORT=3000"]
