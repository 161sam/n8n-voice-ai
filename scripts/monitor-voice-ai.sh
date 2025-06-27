#!/bin/bash
# monitor-voice-ai.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 n8n Voice AI System Health Check"
echo "=================================="

# Check Docker services
echo -e "\n📋 Docker Services Status:"
docker-compose ps

# Check disk usage
echo -e "\n💾 Disk Usage:"
df -h | grep -E "(Filesystem|/dev/)"

# Check memory usage
echo -e "\n🧠 Memory Usage:"
free -h

# Check CPU usage
echo -e "\n⚡ CPU Usage:"
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1 "%"}'

# Check n8n health
echo -e "\n🤖 n8n Health:"
if curl -s http://localhost:5678/healthz > /dev/null; then
    echo -e "${GREEN}✅ n8n is healthy${NC}"
else
    echo -e "${RED}❌ n8n is not responding${NC}"
fi

# Check database connection
echo -e "\n🗄️ Database Health:"
if docker exec postgres-voice-ai pg_isready -U n8n_voice_ai > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PostgreSQL is healthy${NC}"
else
    echo -e "${RED}❌ PostgreSQL connection failed${NC}"
fi

# Check Ollama
echo -e "\n🦙 Ollama Health:"
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo -e "${GREEN}✅ Ollama is healthy${NC}"
    echo "Available models:"
    curl -s http://localhost:11434/api/tags | jq -r '.models[].name' | sed 's/^/  - /'
else
    echo -e "${RED}❌ Ollama is not responding${NC}"
fi

# Check Whisper server
echo -e "\n🎙️ Whisper Server Health:"
if curl -s http://localhost:8080/health > /dev/null; then
    echo -e "${GREEN}✅ Whisper server is healthy${NC}"
else
    echo -e "${RED}❌ Whisper server is not responding${NC}"
fi

# Check recent logs for errors
echo -e "\n📋 Recent Error Logs (last 10 lines):"
docker-compose logs --tail=10 | grep -i error | tail -5

# Check workflow execution stats
echo -e "\n📊 Workflow Stats (last 24 hours):"
docker exec postgres-voice-ai psql -U n8n_voice_ai -d n8n_voice_ai -c "
SELECT 
    COUNT(*) as total_interactions,
    AVG(processing_time) as avg_processing_time_ms,
    MAX(processing_time) as max_processing_time_ms
FROM voice_interactions 
WHERE created_at >= NOW() - INTERVAL '24 hours';" 2>/dev/null || echo "Unable to fetch workflow stats"

echo -e "\n✅ Health check complete!"
