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
