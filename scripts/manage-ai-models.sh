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
