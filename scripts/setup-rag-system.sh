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
