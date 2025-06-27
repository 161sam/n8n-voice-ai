#!/bin/bash
# setup-auth-service.sh - OAuth2/JWT authentication setup

set -e

AUTH_DIR="/opt/n8n-voice-ai/auth"
JWT_SECRET=$(openssl rand -hex 32)
OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID:-"voice-ai-client"}
OAUTH_CLIENT_SECRET=$(openssl rand -hex 16)

echo "🔑 Setting up authentication service"

# Create auth directory
mkdir -p "$AUTH_DIR"/{config,data}

# Generate JWT keys
openssl genrsa -out "$AUTH_DIR/jwt-private.pem" 2048
openssl rsa -in "$AUTH_DIR/jwt-private.pem" -pubout -out "$AUTH_DIR/jwt-public.pem"

# Create OAuth2 configuration
cat > "$AUTH_DIR/config/oauth2.yml" << EOF
server:
  host: 0.0.0.0
  port: 8080

jwt:
  private_key_file: /auth/jwt-private.pem
  public_key_file: /auth/jwt-public.pem
  issuer: voice-ai-system
  expiry: 24h

oauth2:
  providers:
    google:
      client_id: ${GOOGLE_CLIENT_ID:-""}
      client_secret: ${GOOGLE_CLIENT_SECRET:-""}
      scopes: ["openid", "profile", "email"]
    github:
      client_id: ${GITHUB_CLIENT_ID:-""}
      client_secret: ${GITHUB_CLIENT_SECRET:-""}
      scopes: ["user:email"]

database:
  type: postgres
  host: postgres
  port: 5432
  database: n8n_voice_ai
  username: n8n_voice_ai
  password: ${POSTGRES_PASSWORD}

security:
  bcrypt_cost: 12
  rate_limit:
    requests_per_minute: 60
    burst: 10
EOF

# Create Docker service for auth
cat > "$AUTH_DIR/docker-compose.auth.yml" << EOF
version: '3.8'

services:
  auth-service:
    image: ory/hydra:v2.2
    container_name: voice-ai-auth
    restart: unless-stopped
    ports:
      - "4444:4444"  # Public API
      - "4445:4445"  # Admin API
    environment:
      - DSN=postgres://n8n_voice_ai:${POSTGRES_PASSWORD}@postgres:5432/n8n_voice_ai?sslmode=disable
      - URLS_SELF_ISSUER=https://auth.${DOMAIN:-localhost}
      - URLS_CONSENT=https://auth.${DOMAIN:-localhost}/consent
      - URLS_LOGIN=https://auth.${DOMAIN:-localhost}/login
      - SECRETS_SYSTEM=${JWT_SECRET}
    volumes:
      - ./config:/etc/config
      - ./data:/var/lib/hydra
    networks:
      - ai-network
    depends_on:
      - postgres

networks:
  ai-network:
    external: true
EOF

# Set permissions
chmod 600 "$AUTH_DIR"/*.pem
chmod 644 "$AUTH_DIR"/config/*

echo "✅ Authentication service configured"
echo "📋 OAuth2 Client ID: $OAUTH_CLIENT_ID"
echo "🔐 OAuth2 Client Secret: $OAUTH_CLIENT_SECRET"
echo "🔑 JWT Secret: $JWT_SECRET"
