## ⚙️ **TECHNISCHE SPEZIFIKATION**

### **3.1 Architektur-Redesign**

#### **Modernisierte Containerisierung**
```yaml
# Improved Docker Compose Structure
version: '3.8'

services:
  # API Gateway Layer
  api-gateway:
    image: traefik:v3.1
    ports: ["80:80", "443:443"]
    volumes:
      - ./traefik:/etc/traefik
    labels:
      - "traefik.enable=true"

  # Voice Processing Pipeline
  voice-processor:
    build: ./voice-processor
    environment:
      - WHISPER_MODEL=large-v3
      - OLLAMA_MODEL=llama3.2:8b
      - TTS_MODEL=kokoro-v2
    volumes:
      - ./audio-temp:/tmp/audio
    deploy:
      replicas: 3
      resources:
        limits: {memory: 8G, cpus: '4'}

  # Real-time Communication
  webrtc-gateway:
    image: mediasoup/server:latest
    ports: ["3000:3000", "40000-49999:40000-49999/udp"]
    environment:
      - NODE_ENV=production

  # RAG & Knowledge Base
  vector-db:
    image: qdrant/qdrant:latest
    ports: ["6333:6333"]
    volumes:
      - qdrant_data:/qdrant/storage

  # Enhanced Monitoring
  observability:
    image: grafana/alloy:latest
    volumes:
      - ./alloy:/etc/alloy
    environment:
      - GRAFANA_CLOUD_API_KEY=${GRAFANA_CLOUD_KEY}
```

#### **Microservices-basierte Architektur**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Gateway   │────│  Voice Gateway  │────│   Audio Proc.   │
│    (Traefik)    │    │   (WebRTC)      │    │   (Whisper++)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Auth Service  │    │  Session Mgmt   │    │  LLM Gateway    │
│   (OAuth2)      │    │   (Redis)       │    │   (Ollama)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   RAG Service   │    │  TTS Service    │    │  Data Pipeline  │
│   (Qdrant)      │    │   (Kokoro)      │    │ (PostgreSQL)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### **3.2 Erweiterte n8n Workflows**

#### **Real-time Voice Processing Workflow**
```javascript
// Modernized n8n Workflow Structure
{
  "nodes": [
    {
      "name": "WebSocket Voice Input",
      "type": "n8n-nodes-base.websocket",
      "parameters": {
        "path": "/voice-stream",
        "authentication": "jwtAuth"
      }
    },
    {
      "name": "Voice Activity Detection",
      "type": "n8n-nodes-base.code",
      "parameters": {
        "jsCode": `
          const audioChunk = $binary.audio;
          const vadResult = await detectVoiceActivity(audioChunk);
          if (vadResult.isSpeech) {
            return { json: { processAudio: true, confidence: vadResult.confidence }};
          }
          return { json: { processAudio: false }};
        `
      }
    },
    {
      "name": "Streaming STT",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://whisper-streaming:8080/v1/realtime",
        "method": "POST",
        "sendBinaryData": true,
        "bodyContentType": "multipart-form-data"
      }
    }
  ]
}
```

### **3.3 Enhanced Data Layer**

#### **PostgreSQL Schema Evolution**
```sql
-- Enhanced Database Schema
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    voice_profile_id UUID,
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE voice_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    session_token VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(20) DEFAULT 'active',
    voice_settings JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE TABLE voice_interactions_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES voice_sessions(id),
    interaction_sequence INTEGER,
    input_audio_path TEXT,
    transcription TEXT NOT NULL,
    intent_classification JSONB,
    llm_response TEXT NOT NULL,
    output_audio_path TEXT,
    processing_metrics JSONB,
    user_feedback JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE knowledge_base (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_hash VARCHAR(64) UNIQUE NOT NULL,
    content TEXT NOT NULL,
    embeddings VECTOR(1536),
    metadata JSONB DEFAULT '{}',
    access_level VARCHAR(20) DEFAULT 'public',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for Performance
CREATE INDEX idx_voice_interactions_session ON voice_interactions_v2(session_id);
CREATE INDEX idx_voice_interactions_created ON voice_interactions_v2(created_at);
CREATE INDEX idx_knowledge_embeddings ON knowledge_base USING ivfflat (embeddings vector_cosine_ops);
```
