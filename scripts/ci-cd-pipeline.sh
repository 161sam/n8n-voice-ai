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
