# n8n-voice-ai
n8n Voice AI Agent with Continuous Learning
---

## **Quick Setup for Your Proxmox VM:**

1. **Create the directory structure:**
```bash
sudo mkdir -p /opt/n8n-voice-ai/{data,config,backups}
cd /opt/n8n-voice-ai
```

2. **Copy the corrected workflows** from the artifact above

3. **Import order:**
   - First: Logging Sub-Workflow 
   - Second: Feedback Collection Sub-Workflow
   - Third: Continuous Learning Pipeline
   - Fourth: Main Workflow

4. **Update environment variables** with the actual workflow IDs after import

The corrected JSON should now import cleanly without any "propertyValues" or "property option" errors. Each workflow uses the current n8n parameter structures and should work with your Docker/Proxmox setup.

---

## Key Features Summary

### 🎯 **Core Capabilities**
- **Full local processing** - No cloud dependencies
- **Voice-to-voice interaction** - Complete STT→LLM→TTS pipeline
- **Continuous learning** - Weekly automated fine-tuning
- **Production-ready** - Comprehensive error handling, monitoring, and logging
- **Modular architecture** - Easy to extend and maintain

### 🔧 **Technical Components**
- **Whisper.cpp** for speech-to-text (16kHz optimized)
- **Ollama** for local LLM inference with model switching
- **Kokoro TTS** for natural speech synthesis
- **PostgreSQL** for training data and metadata storage
- **Redis** for queue management and caching
- **FFmpeg** for audio preprocessing and format conversion

### 🚀 **Production Features**
- **Docker containerization** with GPU support
- **Proxmox VM optimization** for AI workloads
- **Traefik reverse proxy** with SSL termination
- **Prometheus + Grafana** monitoring stack
- **Automated backups** with rotation policies
- **Health checks** and service recovery

### 📊 **Continuous Learning Pipeline**
- **User feedback collection** via webhooks
- **Training data validation** and quality checks
- **Automated model versioning** and rollback capabilities
- **Weekly fine-tuning** with performance tracking
- **A/B testing** framework for model deployment

### 🔐 **Security & Compliance**
- **End-to-end encryption** for sensitive data
- **Authentication** and authorization controls
- **Audit logging** for all interactions
- **Data retention policies** and cleanup automation
- **Network isolation** between services

## 🔧 **Important Fixes Applied**

### **Main Workflow Corrections:**
1. **Set Node**: Changed from deprecated `assignments` structure to current `fields.values` format
2. **Node IDs**: Generated proper unique UUIDs instead of simple names
3. **If Node**: Updated condition structure with proper `id` fields
4. **HTTP Request**: Corrected parameter structure for newer typeVersion 4.2
5. **Execute Workflow**: Fixed parameter structure for sub-workflow calls
6. **Expression Syntax**: Updated node references to use proper `$('NodeName').item.json` format

### **Sub-Workflow Corrections:**
1. **PostgreSQL Node**: Updated to use proper `schema` and `table` resource locator format
2. **Schedule Trigger**: Fixed cron expression structure
3. **Execute Workflow Trigger**: Simplified parameter structure
4. **Condition Logic**: Updated If node condition structure with proper IDs

### **Real Docker/Proxmox Paths:**

For your Proxmox VM setup, use these realistic paths:

```bash
# VM Directory Structure
/opt/n8n-voice-ai/
├── docker-compose.yml
├── .env
├── data/
│   ├── n8n/              # n8n workflow data
│   ├── postgres/         # Database files
│   ├── shared/           # Audio processing temp files
│   ├── models/           # AI models storage
│   └── logs/             # Application logs
├── config/
│   ├── traefik.yml
│   ├── prometheus.yml
│   └── grafana/
└── backups/              # Automated backups

# Docker Volumes (mapped to host)
volumes:
  - /opt/n8n-voice-ai/data/n8n:/home/node/.n8n
  - /opt/n8n-voice-ai/data/shared:/tmp/shared
  - /opt/n8n-voice-ai/data/models:/models
  - /opt/n8n-voice-ai/logs:/var/log
```

### **Deployment Steps for Proxmox:**

1. **Create VM** (recommended specs for AI workload):
```bash
# VM Configuration
CPU: 16 cores (host passthrough)
RAM: 32GB 
Storage: 500GB NVMe SSD
Network: vmbr0 (bridged)
```

2. **Setup Environment**:
```bash
# SSH into your VM
ssh user@your-vm-ip

# Create directory structure
sudo mkdir -p /opt/n8n-voice-ai/{data/{n8n,postgres,shared,models,logs},config,backups}
sudo chown -R $USER:$USER /opt/n8n-voice-ai

# Copy files
cd /opt/n8n-voice-ai
# Copy the docker-compose.yml and .env files here
```

3. **Configure Environment Variables**:
```bash
# In your .env file, use your actual Proxmox VM IP
N8N_HOST=192.168.1.100  # Your VM IP
WEBHOOK_URL=http://192.168.1.100:5678/

# Database connection (internal Docker network)
POSTGRES_HOST=postgres
OLLAMA_HOST=ollama:11434
WHISPER_API_URL=http://whisper-server:8080
```

4. **Deploy Services**:
```bash
# Pull and start services
docker-compose pull
docker-compose up -d

# Check service health
docker-compose ps
docker-compose logs -f n8n
```

### **Testing the Workflow:**

1. **Import Workflows**:
   - Open n8n at `http://your-vm-ip:5678`
   - Go to Settings → Import from file
   - Import main workflow first, then sub-workflows
   - Update workflow IDs in environment variables

2. **Test Audio Processing**:
```bash
# Test webhook with audio file
curl -X POST \
  -H "Content-Type: multipart/form-data" \
  -F "audio=@test-audio.wav" \
  http://your-vm-ip:5678/webhook/voice-input
```

3. **Monitor Performance**:
   - Grafana: `http://your-vm-ip:3000`
   - Prometheus: `http://your-vm-ip:9090`
   - n8n Executions: Check workflow execution logs

### **Production Notes:**

- **Security**: Configure firewall rules in Proxmox for only necessary ports
- **Backups**: The backup script runs automatically daily at 2 AM
- **SSL**: Configure Traefik with Let's Encrypt for production domains
- **Monitoring**: Set up alerts in Grafana for system resource usage
- **Model Updates**: Use the fine-tuning pipeline weekly to improve performance
