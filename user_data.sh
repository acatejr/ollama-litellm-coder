#!/bin/bash
set -e

# Update packages and install Docker
apt-get update
apt-get install -y curl docker.io docker-compose-v2

systemctl start docker
systemctl enable docker

# Create working directory
mkdir -p /opt/ai-stack
cd /opt/ai-stack

# 1. Create LiteLLM configuration with speed optimizations
cat <<EOF > litellm-config.yaml
model_list:
  - model_name: qwen2.5-coder-3b
    litellm_params:
      model: ollama/qwen2.5-coder:3b
      api_base: "http://ollama:11434"
      num_thread: 4          # Pin threads to match 4 vCPUs (prevents CPU thrashing)
      num_ctx: 2048          # Halves memory bandwidth usage vs 4096 default
      keep_alive: -1         # Keeps model permanently loaded in RAM (no cold starts)
EOF

# 2. Create Docker Compose setup
cat <<EOF > docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: litellm_db
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: litellmpassword
      POSTGRES_DB: litellm
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_NUM_PARALLEL=1       # Directs 100% CPU to a single prompt at a time
      - OLLAMA_MAX_LOADED_MODELS=1   # Prevents RAM swapping
      - OLLAMA_KEEP_ALIVE=-1         # Prevents unloading model on idle
    volumes:
      - ollama_storage:/root/.ollama
    restart: unless-stopped

  ollama-pull-model:
    image: curlimages/curl:latest
    container_name: ollama_pull_model
    depends_on:
      - ollama
    entrypoint: >
      /bin/sh -c "
      echo 'Waiting for Ollama service...';
      while ! curl -s http://ollama:11434/api/tags > /dev/null; do sleep 2; done;
      echo 'Pulling qwen2.5-coder:3b model...';
      curl -X POST http://ollama:11434/api/pull -d '{\"name\": \"qwen2.5-coder:3b\"}';
      echo 'Model pull completed.';
      "

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    ports:
      - "4000:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://litellm:litellmpassword@postgres:5432/litellm
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
    command: [ "--config", "/app/config.yaml", "--port", "4000" ]
    depends_on:
      postgres:
        condition: service_healthy
      ollama:
        condition: service_started
    restart: unless-stopped

volumes:
  ollama_storage:
  postgres_data:
EOF

# Launch Docker Compose stack
docker compose up -d