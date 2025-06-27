# Fehlende Skripte und erweiterte Workflows für Voice AI Projekt

## 📁 **1. SECURITY & AUTHENTICATION SCRIPTS**

### **scripts/setup-ssl-certificates.sh**
```bash
#!/bin/bash
# setup-ssl-certificates.sh - Automated SSL certificate setup

set -e

DOMAIN=${1:-"localhost"}
CERT_DIR="/opt/n8n-voice-ai/certs"
ACME_EMAIL=${ACME_EMAIL:-"admin@${DOMAIN}"}

echo "🔐 Setting up SSL certificates for domain: $DOMAIN"

# Create certificate directory
mkdir -p "$CERT_DIR"

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-dns-cloudflare
fi

# Generate Let's Encrypt certificates
if [ "$DOMAIN" != "localhost" ]; then
    echo "Generating Let's Encrypt certificate for $DOMAIN"
    sudo certbot certonly \
        --standalone \
        --email "$ACME_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        --cert-path "$CERT_DIR/cert.pem" \
        --key-path "$CERT_DIR/key.pem" \
        --fullchain-path "$CERT_DIR/fullchain.pem"
else
    echo "Generating self-signed certificate for localhost"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"
    cp "$CERT_DIR/cert.pem" "$CERT_DIR/fullchain.pem"
fi

# Set proper permissions
sudo chown -R $USER:$USER "$CERT_DIR"
chmod 600 "$CERT_DIR"/key.pem
chmod 644 "$CERT_DIR"/{cert,fullchain}.pem

# Setup certificate renewal
if [ "$DOMAIN" != "localhost" ]; then
    echo "Setting up automatic certificate renewal"
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
fi

echo "✅ SSL certificates ready at: $CERT_DIR"
```

### **scripts/setup-auth-service.sh**
```bash
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
```

## 🌐 **2. REAL-TIME COMMUNICATION SCRIPTS**

### **scripts/setup-webrtc-gateway.sh**
```bash
#!/bin/bash
# setup-webrtc-gateway.sh - WebRTC gateway for real-time voice

set -e

WEBRTC_DIR="/opt/n8n-voice-ai/webrtc"
STUN_SERVER=${STUN_SERVER:-"stun:stun.l.google.com:19302"}

echo "📡 Setting up WebRTC gateway"

# Create WebRTC directory
mkdir -p "$WEBRTC_DIR"/{config,logs}

# Create WebRTC configuration
cat > "$WEBRTC_DIR/config/webrtc.json" << EOF
{
  "server": {
    "host": "0.0.0.0",
    "port": 3000,
    "ssl": {
      "cert": "/certs/fullchain.pem",
      "key": "/certs/key.pem"
    }
  },
  "webrtc": {
    "iceServers": [
      { "urls": "${STUN_SERVER}" },
      {
        "urls": "turn:${TURN_SERVER:-localhost:3478}",
        "username": "${TURN_USERNAME:-voice-ai}",
        "credential": "${TURN_PASSWORD:-$(openssl rand -hex 16)}"
      }
    ],
    "iceTransportPolicy": "all",
    "bundlePolicy": "balanced"
  },
  "audio": {
    "codecs": ["opus", "pcmu", "pcma"],
    "sampleRate": 16000,
    "channels": 1,
    "bitrate": 32000
  },
  "recording": {
    "enabled": true,
    "format": "wav",
    "directory": "/tmp/recordings"
  }
}
EOF

# Create WebRTC Docker service
cat > "$WEBRTC_DIR/docker-compose.webrtc.yml" << EOF
version: '3.8'

services:
  webrtc-gateway:
    image: ghcr.io/livekit/livekit-server:latest
    container_name: voice-ai-webrtc
    restart: unless-stopped
    ports:
      - "7880:7880"     # HTTP
      - "7881:7881"     # gRPC
      - "7882:7882/udp" # TURN/UDP
    environment:
      - LIVEKIT_CONFIG_FILE=/config/livekit.yaml
    volumes:
      - ./config:/config
      - ../certs:/certs
      - shared_audio:/tmp/recordings
    networks:
      - ai-network

  coturn:
    image: coturn/coturn:latest
    container_name: voice-ai-turn
    restart: unless-stopped
    ports:
      - "3478:3478"
      - "3478:3478/udp"
      - "49152-65535:49152-65535/udp"
    volumes:
      - ./config/turnserver.conf:/etc/turnserver.conf
    networks:
      - ai-network

volumes:
  shared_audio:
    external: true

networks:
  ai-network:
    external: true
EOF

# Create TURN server configuration
cat > "$WEBRTC_DIR/config/turnserver.conf" << EOF
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
external-ip=${EXTERNAL_IP:-$(curl -s ipinfo.io/ip)}
relay-ip=0.0.0.0
fingerprint
lt-cred-mech
user=${TURN_USERNAME:-voice-ai}:${TURN_PASSWORD:-$(openssl rand -hex 16)}
realm=voice-ai.local
total-quota=100
stale-nonce=600
cert=/certs/fullchain.pem
pkey=/certs/key.pem
cipher-list="ECDH+AESGCM:ECDH+CHACHA20:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS"
no-loopback-peers
no-multicast-peers
EOF

echo "✅ WebRTC gateway configured"
echo "📡 STUN Server: $STUN_SERVER"
echo "🔄 TURN Username: ${TURN_USERNAME:-voice-ai}"
```

## 🤖 **3. AI MODEL MANAGEMENT SCRIPTS**

### **scripts/manage-ai-models.sh**
```bash
#!/bin/bash
# manage-ai-models.sh - AI model lifecycle management

set -e

MODEL_DIR="/opt/n8n-voice-ai/models"
OLLAMA_HOST=${OLLAMA_HOST:-"localhost:11434"}
MODELS_CONFIG="$MODEL_DIR/models.json"

# Supported models configuration
SUPPORTED_MODELS=(
    "llama3.2:1b"
    "llama3.2:3b" 
    "llama3.2:8b"
    "llama3.2:70b"
    "qwen2.5:7b"
    "qwen2.5:14b"
    "mistral:7b"
    "codellama:7b"
)

usage() {
    echo "Usage: $0 {list|pull|remove|update|benchmark|optimize} [model_name]"
    echo ""
    echo "Commands:"
    echo "  list       - List all available models"
    echo "  pull       - Download and install a model"
    echo "  remove     - Remove a model"
    echo "  update     - Update all models to latest versions"
    echo "  benchmark  - Run performance benchmarks"
    echo "  optimize   - Optimize model performance"
    exit 1
}

list_models() {
    echo "🤖 Available models:"
    curl -s "$OLLAMA_HOST/api/tags" | jq -r '.models[] | "\(.name) - \(.size/1024/1024/1024 | floor)GB"' || echo "Failed to connect to Ollama"
    
    echo ""
    echo "📦 Supported models for auto-installation:"
    printf '%s\n' "${SUPPORTED_MODELS[@]}"
}

pull_model() {
    local model_name="$1"
    if [ -z "$model_name" ]; then
        echo "❌ Please specify a model name"
        exit 1
    fi
    
    echo "📥 Pulling model: $model_name"
    curl -X POST "$OLLAMA_HOST/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$model_name\"}" \
        --progress-bar
    
    echo "✅ Model $model_name installed successfully"
}

remove_model() {
    local model_name="$1"
    if [ -z "$model_name" ]; then
        echo "❌ Please specify a model name"
        exit 1
    fi
    
    echo "🗑️ Removing model: $model_name"
    curl -X DELETE "$OLLAMA_HOST/api/delete" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$model_name\"}"
    
    echo "✅ Model $model_name removed successfully"
}

update_models() {
    echo "🔄 Updating all models..."
    
    # Get current models
    local models=$(curl -s "$OLLAMA_HOST/api/tags" | jq -r '.models[].name')
    
    for model in $models; do
        echo "Updating $model..."
        pull_model "$model"
    done
    
    echo "✅ All models updated"
}

benchmark_models() {
    echo "⚡ Running model benchmarks..."
    
    local test_prompt="Explain the concept of artificial intelligence in one paragraph."
    local models=$(curl -s "$OLLAMA_HOST/api/tags" | jq -r '.models[].name')
    
    echo "Model,Response Time (ms),Tokens/sec,Memory Usage (MB)" > "$MODEL_DIR/benchmark_results.csv"
    
    for model in $models; do
        echo "Benchmarking $model..."
        
        local start_time=$(date +%s%3N)
        local response=$(curl -s "$OLLAMA_HOST/api/generate" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$model\", \"prompt\": \"$test_prompt\", \"stream\": false}")
        local end_time=$(date +%s%3N)
        
        local response_time=$((end_time - start_time))
        local tokens=$(echo "$response" | jq -r '.eval_count // 0')
        local tokens_per_sec=$(echo "scale=2; $tokens * 1000 / $response_time" | bc -l)
        
        # Get memory usage (approximation)
        local memory_usage=$(docker stats ollama-voice-ai --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1)
        
        echo "$model,$response_time,$tokens_per_sec,$memory_usage" >> "$MODEL_DIR/benchmark_results.csv"
    done
    
    echo "✅ Benchmark results saved to $MODEL_DIR/benchmark_results.csv"
}

optimize_models() {
    echo "🔧 Optimizing model performance..."
    
    # Create optimized Modelfiles for quantized versions
    for model in "${SUPPORTED_MODELS[@]}"; do
        if curl -s "$OLLAMA_HOST/api/tags" | jq -e ".models[] | select(.name == \"$model\")" > /dev/null; then
            echo "Creating optimized version of $model..."
            
            cat > "$MODEL_DIR/Modelfile.${model//[:.]/_}.optimized" << EOF
FROM $model

# Performance optimizations
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 4096
PARAMETER num_predict 512

# Memory optimizations
PARAMETER num_gpu_layers 32
PARAMETER num_thread 8
PARAMETER use_mlock true
PARAMETER use_mmap true

SYSTEM """You are a helpful AI assistant optimized for voice interactions. 
Keep responses concise and conversational. Avoid overly technical language unless specifically requested."""
EOF
            
            # Create optimized model
            ollama create "${model}-optimized" -f "$MODEL_DIR/Modelfile.${model//[:.]/_}.optimized"
        fi
    done
    
    echo "✅ Model optimization complete"
}

# Main script logic
case "${1:-list}" in
    list)
        list_models
        ;;
    pull)
        pull_model "$2"
        ;;
    remove)
        remove_model "$2"
        ;;
    update)
        update_models
        ;;
    benchmark)
        benchmark_models
        ;;
    optimize)
        optimize_models
        ;;
    *)
        usage
        ;;
esac
```

## 📊 **4. MONITORING & ANALYTICS SCRIPTS**

### **scripts/setup-advanced-monitoring.sh**
```bash
#!/bin/bash
# setup-advanced-monitoring.sh - Enhanced monitoring stack

set -e

MONITORING_DIR="/opt/n8n-voice-ai/monitoring"
GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-$(openssl rand -hex 16)}

echo "📊 Setting up advanced monitoring stack"

# Create monitoring directory
mkdir -p "$MONITORING_DIR"/{grafana/{dashboards,provisioning/{dashboards,datasources,alerting}},prometheus/rules,loki,jaeger}

# Enhanced Prometheus configuration
cat > "$MONITORING_DIR/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'voice-ai-production'
    environment: '${ENVIRONMENT:-production}'

rule_files:
  - "rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Application metrics
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'voice-processor'
    static_configs:
      - targets: ['whisper-server:8080', 'kokoro-tts:8880']
    metrics_path: /metrics

  - job_name: 'ollama'
    static_configs:
      - targets: ['ollama:11434']
    metrics_path: /api/metrics

  # Infrastructure metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']

  # Custom voice AI metrics
  - job_name: 'voice-analytics'
    static_configs:
      - targets: ['voice-analytics:9090']
    scrape_interval: 10s

remote_write:
  - url: "${GRAFANA_CLOUD_PROMETHEUS_URL:-}"
    basic_auth:
      username: "${GRAFANA_CLOUD_PROMETHEUS_USER:-}"
      password: "${GRAFANA_CLOUD_API_KEY:-}"
EOF

# Voice AI specific alerting rules
cat > "$MONITORING_DIR/prometheus/rules/voice_ai_alerts.yml" << EOF
groups:
  - name: voice_ai_alerts
    rules:
      # Voice processing performance
      - alert: HighVoiceProcessingLatency
        expr: histogram_quantile(0.95, voice_processing_duration_seconds) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High voice processing latency detected"
          description: "95th percentile latency is {{ \$value }}s"

      - alert: VoiceProcessingErrors
        expr: rate(voice_processing_errors_total[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High voice processing error rate"
          description: "Error rate is {{ \$value }} errors/sec"

      # Model performance
      - alert: LLMResponseTime
        expr: histogram_quantile(0.95, llm_response_duration_seconds) > 5
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "LLM response time is too high"

      - alert: STTAccuracyDrop
        expr: stt_accuracy_score < 0.9
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "STT accuracy has dropped below 90%"

      # Resource utilization
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"

      # Storage alerts
      - alert: LowDiskSpace
        expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space on {{ \$labels.instance }}"

      # Application health
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ \$labels.job }} service is down"

      - alert: DatabaseConnectionIssues
        expr: increase(postgres_connection_errors_total[5m]) > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Database connection issues detected"
EOF

# Grafana datasource configuration
cat > "$MONITORING_DIR/grafana/provisioning/datasources/datasources.yml" << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true

  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    editable: true

  - name: PostgreSQL
    type: postgres
    url: postgres:5432
    database: n8n_voice_ai
    user: n8n_voice_ai
    secureJsonData:
      password: '${POSTGRES_PASSWORD}'
    jsonData:
      sslmode: 'disable'
      maxOpenConns: 10
      maxIdleConns: 2
      connMaxLifetime: 14400
EOF

# Voice AI dashboard
cat > "$MONITORING_DIR/grafana/dashboards/voice-ai-overview.json" << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Voice AI - System Overview",
    "tags": ["voice-ai", "overview"],
    "timezone": "browser",
    "refresh": "30s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "panels": [
      {
        "title": "Voice Processing Pipeline",
        "type": "stat",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "rate(voice_interactions_total[5m])",
            "legendFormat": "Interactions/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "red", "value": 80}
              ]
            }
          }
        }
      },
      {
        "title": "Average Processing Latency",
        "type": "stat",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "histogram_quantile(0.5, voice_processing_duration_seconds)",
            "legendFormat": "P50 Latency"
          }
        ]
      },
      {
        "title": "Voice Quality Metrics",
        "type": "graph",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
        "targets": [
          {
            "expr": "stt_accuracy_score",
            "legendFormat": "STT Accuracy"
          },
          {
            "expr": "tts_quality_score",
            "legendFormat": "TTS Quality"
          },
          {
            "expr": "user_satisfaction_score",
            "legendFormat": "User Satisfaction"
          }
        ],
        "yAxes": [
          {
            "min": 0,
            "max": 1,
            "unit": "percentunit"
          }
        ]
      }
    ]
  }
}
EOF

echo "✅ Advanced monitoring stack configured"
echo "🔑 Grafana admin password: $GRAFANA_ADMIN_PASSWORD"
```

## 🚀 **5. RAG & KNOWLEDGE BASE SCRIPTS**

### **scripts/setup-rag-system.sh**
```bash
#!/bin/bash
# setup-rag-system.sh - RAG system with vector database

set -e

RAG_DIR="/opt/n8n-voice-ai/rag"
QDRANT_API_KEY=$(openssl rand -hex 32)

echo "🧠 Setting up RAG (Retrieval-Augmented Generation) system"

# Create RAG directory structure
mkdir -p "$RAG_DIR"/{config,data,documents,embeddings}

# Qdrant configuration
cat > "$RAG_DIR/config/qdrant.yml" << EOF
service:
  host: 0.0.0.0
  http_port: 6333
  grpc_port: 6334

storage:
  storage_path: /qdrant/storage
  snapshots_path: /qdrant/snapshots
  temp_path: /qdrant/temp

cluster:
  enabled: false

service:
  enable_cors: true

telemetry_disabled: true

log_level: INFO
EOF

# Document processing pipeline
cat > "$RAG_DIR/document_processor.py" << 'EOF'
#!/usr/bin/env python3
"""Document processing pipeline for RAG system"""

import os
import json
import hashlib
from pathlib import Path
from typing import List, Dict, Any
import asyncio
import aiofiles
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
import openai
from sentence_transformers import SentenceTransformer
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.document_loaders import (
    TextLoader, PDFLoader, UnstructuredWordDocumentLoader
)

class DocumentProcessor:
    def __init__(self, qdrant_url: str = "http://localhost:6333"):
        self.qdrant = QdrantClient(url=qdrant_url)
        self.embedder = SentenceTransformer('all-MiniLM-L6-v2')
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200
        )
        self.collection_name = "voice_ai_knowledge"
        
    async def initialize_collection(self):
        """Initialize Qdrant collection for embeddings"""
        try:
            self.qdrant.create_collection(
                collection_name=self.collection_name,
                vectors_config=VectorParams(
                    size=384,  # all-MiniLM-L6-v2 dimension
                    distance=Distance.COSINE
                )
            )
            print(f"✅ Created collection: {self.collection_name}")
        except Exception as e:
            print(f"Collection may already exist: {e}")
    
    def load_document(self, file_path: str) -> List[str]:
        """Load and split document into chunks"""
        file_extension = Path(file_path).suffix.lower()
        
        if file_extension == '.txt':
            loader = TextLoader(file_path)
        elif file_extension == '.pdf':
            loader = PDFLoader(file_path)
        elif file_extension in ['.docx', '.doc']:
            loader = UnstructuredWordDocumentLoader(file_path)
        else:
            raise ValueError(f"Unsupported file type: {file_extension}")
        
        documents = loader.load()
        chunks = self.text_splitter.split_documents(documents)
        
        return [chunk.page_content for chunk in chunks]
    
    def generate_embeddings(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for text chunks"""
        return self.embedder.encode(texts).tolist()
    
    async def index_document(self, file_path: str, metadata: Dict[str, Any] = None):
        """Index a document in the vector database"""
        print(f"📄 Processing document: {file_path}")
        
        # Generate document hash for deduplication
        with open(file_path, 'rb') as f:
            doc_hash = hashlib.sha256(f.read()).hexdigest()
        
        # Load and chunk document
        chunks = self.load_document(file_path)
        print(f"📝 Split into {len(chunks)} chunks")
        
        # Generate embeddings
        embeddings = self.generate_embeddings(chunks)
        
        # Prepare points for insertion
        points = []
        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
            point_id = f"{doc_hash}_{i}"
            point = PointStruct(
                id=point_id,
                vector=embedding,
                payload={
                    "text": chunk,
                    "document_path": file_path,
                    "document_hash": doc_hash,
                    "chunk_index": i,
                    "metadata": metadata or {}
                }
            )
            points.append(point)
        
        # Insert into Qdrant
        self.qdrant.upsert(
            collection_name=self.collection_name,
            points=points
        )
        
        print(f"✅ Indexed {len(points)} chunks from {file_path}")
    
    async def search_similar(self, query: str, limit: int = 5) -> List[Dict]:
        """Search for similar chunks"""
        query_embedding = self.embedder.encode([query])[0].tolist()
        
        results = self.qdrant.search(
            collection_name=self.collection_name,
            query_vector=query_embedding,
            limit=limit
        )
        
        return [
            {
                "text": result.payload["text"],
                "score": result.score,
                "metadata": result.payload.get("metadata", {})
            }
            for result in results
        ]

async def main():
    processor = DocumentProcessor()
    await processor.initialize_collection()
    
    # Process documents in the documents directory
    docs_dir = Path("/rag/documents")
    if docs_dir.exists():
        for file_path in docs_dir.glob("**/*"):
            if file_path.is_file() and file_path.suffix in ['.txt', '.pdf', '.docx', '.doc']:
                await processor.index_document(str(file_path))

if __name__ == "__main__":
    asyncio.run(main())
EOF

# RAG Docker service
cat > "$RAG_DIR/docker-compose.rag.yml" << EOF
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: voice-ai-qdrant
    restart: unless-stopped
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage
      - ./config/qdrant.yml:/qdrant/config/production.yaml
    environment:
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
    networks:
      - ai-network

  embedding-service:
    build:
      context: .
      dockerfile: Dockerfile.embeddings
    container_name: voice-ai-embeddings
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - QDRANT_URL=http://qdrant:6333
      - QDRANT_API_KEY=${QDRANT_API_KEY}
    volumes:
      - ./documents:/app/documents
      - ./embeddings:/app/embeddings
    networks:
      - ai-network
    depends_on:
      - qdrant

volumes:
  qdrant_data:

networks:
  ai-network:
    external: true
EOF

# Dockerfile for embedding service
cat > "$RAG_DIR/Dockerfile.embeddings" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY document_processor.py .
COPY embedding_api.py .

# Create directories
RUN mkdir -p /app/{documents,embeddings}

EXPOSE 8000

CMD ["python", "embedding_api.py"]
EOF

# Requirements for embedding service
cat > "$RAG_DIR/requirements.txt" << EOF
fastapi==0.104.1
uvicorn==0.24.0
qdrant-client==1.7.0
sentence-transformers==2.2.2
langchain==0.0.340
langchain-community==0.0.1
openai==1.3.5
aiofiles==23.2.1
python-multipart==0.0.6
pypdf==3.17.1
unstructured==0.11.6
python-docx==1.1.0
EOF

# Embedding API service
cat > "$RAG_DIR/embedding_api.py" << 'EOF'
#!/usr/bin/env python3
"""FastAPI service for embedding and RAG operations"""

from fastapi import FastAPI, File, UploadFile, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
import os
import tempfile
from document_processor import DocumentProcessor

app = FastAPI(title="Voice AI Embedding Service", version="1.0.0")
processor = DocumentProcessor(qdrant_url=os.getenv("QDRANT_URL", "http://localhost:6333"))

class SearchQuery(BaseModel):
    query: str
    limit: int = 5

class SearchResult(BaseModel):
    text: str
    score: float
    metadata: Dict[str, Any]

@app.on_event("startup")
async def startup_event():
    await processor.initialize_collection()

@app.post("/upload", response_model=Dict[str, str])
async def upload_document(file: UploadFile = File(...)):
    """Upload and index a document"""
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=file.filename) as tmp_file:
            content = await file.read()
            tmp_file.write(content)
            tmp_file_path = tmp_file.name
        
        # Index the document
        await processor.index_document(
            tmp_file_path,
            metadata={"filename": file.filename, "content_type": file.content_type}
        )
        
        # Clean up
        os.unlink(tmp_file_path)
        
        return {"status": "success", "message": f"Document {file.filename} indexed successfully"}
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/search", response_model=List[SearchResult])
async def search_documents(query: SearchQuery):
    """Search for similar document chunks"""
    try:
        results = await processor.search_similar(query.query, query.limit)
        return [SearchResult(**result) for result in results]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

chmod +x "$RAG_DIR/document_processor.py"
chmod +x "$RAG_DIR/embedding_api.py"

echo "✅ RAG system configured"
echo "🔑 Qdrant API Key: $QDRANT_API_KEY"
echo "📚 Upload documents to: $RAG_DIR/documents/"
```

## 🔄 **6. CONTINUOUS INTEGRATION SCRIPTS**

### **scripts/ci-cd-pipeline.sh**
```bash
#!/bin/bash
# ci-cd-pipeline.sh - Continuous integration and deployment

set -e

CI_DIR="/opt/n8n-voice-ai/ci"
DOCKER_REGISTRY=${DOCKER_REGISTRY:-"localhost:5000"}
PROJECT_NAME="voice-ai"

echo "🚀 Setting up CI/CD pipeline"

# Create CI directory
mkdir -p "$CI_DIR"/{github-actions,gitlab-ci,jenkins,tests}

# GitHub Actions workflow
cat > "$CI_DIR/github-actions/ci.yml" << 'EOF'
name: Voice AI CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test_password
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      
      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements-test.txt
    
    - name: Run unit tests
      run: |
        pytest tests/unit/ --cov=src --cov-report=xml
    
    - name: Run integration tests
      run: |
        pytest tests/integration/ -v
      env:
        POSTGRES_URL: postgresql://postgres:test_password@localhost:5432/test_db
        REDIS_URL: redis://localhost:6379/0
    
    - name: Upload coverage reports
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml

  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'
    
    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

  build-and-push:
    needs: [test, security-scan]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix={{branch}}-
    
    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy:
    if: github.ref == 'refs/heads/main'
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: production
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Deploy to production
      run: |
        echo "Deploying to production environment..."
        # Add deployment commands here
EOF

# Test configuration
cat > "$CI_DIR/tests/pytest.ini" << EOF
[tool:pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = 
    --strict-markers
    --disable-warnings
    --verbose
    --tb=short
    --cov-config=.coveragerc
markers =
    unit: Unit tests
    integration: Integration tests
    slow: Slow tests
    voice: Voice processing tests
    llm: LLM related tests
EOF

# Docker Compose for testing
cat > "$CI_DIR/docker-compose.test.yml" << EOF
version: '3.8'

services:
  test-postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: test_password
      POSTGRES_DB: test_db
    ports:
      - "5433:5432"
    tmpfs:
      - /var/lib/postgresql/data

  test-redis:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    tmpfs:
      - /data

  test-whisper:
    image: whisper-test:latest
    build:
      context: ../whisper-test
    ports:
      - "8081:8080"

  test-runner:
    build:
      context: ..
      dockerfile: Dockerfile.test
    volumes:
      - ../tests:/app/tests
      - ../src:/app/src
    environment:
      - POSTGRES_URL=postgresql://postgres:test_password@test-postgres:5432/test_db
      - REDIS_URL=redis://test-redis:6379/0
      - WHISPER_URL=http://test-whisper:8080
    depends_on:
      - test-postgres
      - test-redis
      - test-whisper
    command: pytest tests/ -v --cov=src
EOF

echo "✅ CI/CD pipeline configured"
echo "📁 GitHub Actions workflow: $CI_DIR/github-actions/ci.yml"
echo "🧪 Test configuration: $CI_DIR/tests/"
```

Diese umfassenden Skripte und Workflows ergänzen das bestehende Projekt um kritische Funktionalitäten:

1. **Security & Authentication** - SSL-Zertifikate und OAuth2/JWT-Authentication
2. **Real-time Communication** - WebRTC Gateway für Live-Audio-Verarbeitung  
3. **AI Model Management** - Automatisierte Model-Downloads, Updates und Benchmarking
4. **Advanced Monitoring** - Erweiterte Prometheus/Grafana-Konfiguration mit Voice-AI-spezifischen Metriken
5. **RAG System** - Vector Database mit Qdrant für Knowledge Retrieval
6. **CI/CD Pipeline** - GitHub Actions für automatisierte Tests und Deployments

Diese Komponenten bilden das Fundament für eine produktionsreife, skalierbare Voice AI-Lösung mit modernen DevOps-Praktiken.
