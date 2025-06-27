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
