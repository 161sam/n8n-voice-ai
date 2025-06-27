#!/bin/bash
# deploy-voice-ai.sh

set -e

PROJECT_DIR="/opt/n8n-voice-ai"
BACKUP_DIR="/opt/n8n-voice-ai/backups"

echo "🚀 Deploying n8n Voice AI System..."

# Check if .env file exists
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "❌ .env file not found. Please create it first."
    exit 1
fi

# Create backup of existing deployment
if [ -d "$PROJECT_DIR/data" ]; then
    echo "📦 Creating backup..."
    BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    sudo cp -r "$PROJECT_DIR/data" "$BACKUP_DIR/$BACKUP_NAME/"
    echo "✅ Backup created: $BACKUP_DIR/$BACKUP_NAME"
fi

# Pull latest images
echo "📥 Pulling latest Docker images..."
cd "$PROJECT_DIR"
docker-compose pull

# Deploy services
echo "🔧 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Health checks
echo "🔍 Performing health checks..."
docker-compose ps

# Check n8n
if curl -f http://localhost:5678/healthz > /dev/null 2>&1; then
    echo "✅ n8n is healthy"
else
    echo "❌ n8n health check failed"
fi

# Check Ollama
if curl -f http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✅ Ollama is healthy"
else
    echo "❌ Ollama health check failed"
fi

# Check Whisper
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Whisper server is healthy"
else
    echo "❌ Whisper server health check failed"
fi

# Setup initial models
echo "📚 Setting up AI models..."
docker exec ollama-voice-ai ollama pull llama3.2:8b
docker exec ollama-voice-ai ollama pull llama3.2:1b

echo "🎉 Deployment complete!"
echo "📍 Access n8n at: https://your-domain.com"
echo "📊 Access Grafana at: http://localhost:3000"
echo "📈 Access Prometheus at: http://localhost:9090"
