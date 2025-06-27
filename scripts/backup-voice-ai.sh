#!/bin/bash
# backup-voice-ai.sh

set -e

PROJECT_DIR="/opt/n8n-voice-ai"
BACKUP_DIR="/opt/backups/n8n-voice-ai"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="n8n_voice_ai_backup_$DATE"

echo "📦 Starting backup process..."

# Create backup directory
mkdir -p "$BACKUP_DIR/$BACKUP_NAME"

# Backup PostgreSQL database
echo "🗄️ Backing up PostgreSQL database..."
docker exec postgres-voice-ai pg_dump -U n8n_voice_ai n8n_voice_ai > "$BACKUP_DIR/$BACKUP_NAME/database.sql"

# Backup n8n data
echo "📁 Backing up n8n data..."
docker run --rm \
  -v n8n-voice-ai_n8n_storage:/data \
  -v "$BACKUP_DIR/$BACKUP_NAME":/backup \
  alpine tar czf /backup/n8n_data.tar.gz -C /data .

# Backup shared audio files
echo "🎵 Backing up shared audio files..."
docker run --rm \
  -v n8n-voice-ai_shared_audio:/data \
  -v "$BACKUP_DIR/$BACKUP_NAME":/backup \
  alpine tar czf /backup/shared_audio.tar.gz -C /data .

# Backup Ollama models
echo "🤖 Backing up Ollama models..."
docker run --rm \
  -v n8n-voice-ai_ollama_storage:/data \
  -v "$BACKUP_DIR/$BACKUP_NAME":/backup \
  alpine tar czf /backup/ollama_models.tar.gz -C /data .

# Backup configuration files
echo "⚙️ Backing up configuration files..."
cp "$PROJECT_DIR/docker-compose.yml" "$BACKUP_DIR/$BACKUP_NAME/"
cp "$PROJECT_DIR/.env" "$BACKUP_DIR/$BACKUP_NAME/env.backup"

# Create metadata file
cat > "$BACKUP_DIR/$BACKUP_NAME/backup_metadata.json" << EOF
{
  "backup_date": "$DATE",
  "backup_name": "$BACKUP_NAME",
  "docker_compose_version": "$(docker-compose --version)",
  "system_info": {
    "hostname": "$(hostname)",
    "os": "$(lsb_release -d | cut -f2)",
    "kernel": "$(uname -r)"
  },
  "services": {
    "n8n": "$(docker inspect n8n-voice-ai --format='{{.Config.Image}}')",
    "postgres": "$(docker inspect postgres-voice-ai --format='{{.Config.Image}}')",
    "ollama": "$(docker inspect ollama-voice-ai --format='{{.Config.Image}}')"
  }
}
EOF

# Compress entire backup
echo "🗜️ Compressing backup..."
cd "$BACKUP_DIR"
tar czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "n8n_voice_ai_backup_*.tar.gz" -mtime +7 -delete

echo "✅ Backup completed: $BACKUP_DIR/$BACKUP_NAME.tar.gz"
echo "📊 Backup size: $(du -h "$BACKUP_DIR/$BACKUP_NAME.tar.gz" | cut -f1)"
