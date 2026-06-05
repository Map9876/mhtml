#!/bin/bash
set -e

# 1. 配置 CodeBuddy 模型（紧凑 JSON）
mkdir -p ~/.codebuddy && echo '{"models":[{"id":"/workspace/vllm-qwen3.5","name":"/workspace/vllm-qwen3.5","vendor":"user","url":"http://localhost:8000/v1/chat/completions","apiKey":"","maxOutputTokens":32000,"maxInputTokens":128000,"maxAllowedSize":128000,"supportsToolCall":true,"supportsImages":false,"supportsReasoning":true,"temperature":1}],"availableModels":["/workspace/vllm-qwen3.5"]}' > ~/.codebuddy/models.json

# 2. 安装 Node.js（选择一种）
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# 3. 安装 CodeBuddy CLI
npm install -g @tencent-ai/codebuddy-code

# 4. 设置环境变量（持久化）
if ! grep -q "CODEBUDDY_BASE_URL" ~/.bashrc; then
    echo 'export CODEBUDDY_BASE_URL="http://localhost:8000/v1/chat/completions"' >> ~/.bashrc
        echo 'export CODEBUDDY_API_KEY=""' >> ~/.bashrc
            echo 'export CODEBUDDY_MODEL="/workspace/vllm-qwen3.5"' >> ~/.bashrc
            fi

            echo "Done. Run source ~/.bashrc and then codebuddy."