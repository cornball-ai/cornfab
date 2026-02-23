#!/usr/bin/env bash
set -euo pipefail

# cornfab one-liner installer
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/cornball-ai/cornfab/main/docker/install.sh)"

STACK_DIR="$HOME/cornfab-stack"
CORNFAB_PORT=7803
QWEN3_PORT=7811

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Banner ---
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║           cornfab + Qwen3-TTS             ║"
echo "  ║       Text-to-Speech Web UI Stack         ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo "This will install:"
echo "  - cornfab       Shiny web UI on port $CORNFAB_PORT"
echo "  - qwen3-tts-api GPU TTS backend on port $QWEN3_PORT"
echo ""
echo "Working directory: $STACK_DIR"
echo ""

# --- Prerequisites ---
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        error "$1 is required but not installed."
        echo "  Install: $2"
        return 1
    fi
    ok "$1 found"
}

info "Checking prerequisites..."
MISSING=0
check_cmd docker "https://docs.docker.com/engine/install/" || MISSING=1
check_cmd git "sudo apt install git" || MISSING=1
check_cmd nvidia-smi "https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html" || MISSING=1

if [ "$MISSING" -eq 1 ]; then
    error "Missing prerequisites. Install them and re-run."
    exit 1
fi

# Check nvidia-container-toolkit (docker GPU support)
if ! docker info 2>/dev/null | grep -qi "nvidia\|gpu"; then
    if ! dpkg -l nvidia-container-toolkit &>/dev/null 2>&1; then
        warn "nvidia-container-toolkit may not be installed."
        echo "  Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
        read -rp "Continue anyway? [y/N] " ans
        [[ "$ans" =~ ^[Yy] ]] || exit 1
    fi
fi

# --- GPU Architecture Detection ---
detect_gpu_dockerfile() {
    local gpu_name
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    info "Detected GPU: $gpu_name"

    # Blackwell = RTX 50xx series
    if echo "$gpu_name" | grep -qE "RTX.*(50[0-9]{2}|B[0-9]{3})"; then
        info "Blackwell GPU detected -> using Dockerfile.blackwell"
        echo "blackwell"
    else
        info "Pre-Blackwell GPU detected -> using default Dockerfile"
        echo "default"
    fi
}

GPU_TYPE=$(detect_gpu_dockerfile)

# --- Create working directory ---
mkdir -p "$STACK_DIR"
info "Working directory: $STACK_DIR"

# --- Clone repos ---
clone_repo() {
    local repo="$1" dir="$2"
    if [ -d "$STACK_DIR/$dir" ]; then
        info "$dir already exists, pulling latest..."
        git -C "$STACK_DIR/$dir" pull --ff-only 2>/dev/null || warn "Could not pull $dir (may have local changes)"
    else
        info "Cloning $repo..."
        git clone "https://github.com/$repo.git" "$STACK_DIR/$dir"
    fi
}

clone_repo "cornball-ai/cornfab" "cornfab"
clone_repo "cornball-ai/qwen3-tts-api" "qwen3-tts-api"

# --- Build images ---
info "Building cornfab image..."
docker build -t cornfab:latest -f "$STACK_DIR/cornfab/docker/Dockerfile" "$STACK_DIR/cornfab"

info "Building qwen3-tts-api image..."
if [ "$GPU_TYPE" = "blackwell" ]; then
    docker build -t qwen3-tts-api:latest -f "$STACK_DIR/qwen3-tts-api/Dockerfile.blackwell" "$STACK_DIR/qwen3-tts-api"
else
    docker build -t qwen3-tts-api:latest -f "$STACK_DIR/qwen3-tts-api/Dockerfile" "$STACK_DIR/qwen3-tts-api"
fi

# --- Model Downloads ---
echo ""
echo -e "${BOLD}Qwen3-TTS requires pre-downloaded models.${NC}"
echo ""
echo "  1) CustomVoice only  (~7GB)  - 9 built-in voices"
echo "  2) All three models  (~21GB) - voices + cloning + voice design"
echo "  3) Skip download     - I already have the models"
echo ""
read -rp "Choose [1/2/3]: " MODEL_CHOICE

download_model() {
    local model="$1"
    info "Downloading $model..."
    if command -v huggingface-cli &>/dev/null; then
        huggingface-cli download "$model"
    elif command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
        local pip_cmd="pip3"
        command -v pip3 &>/dev/null || pip_cmd="pip"
        "$pip_cmd" install --quiet huggingface_hub 2>/dev/null
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$model')"
    else
        error "No huggingface-cli or pip found. Install manually:"
        echo "  pip install huggingface_hub"
        echo "  huggingface-cli download $model"
        return 1
    fi
    ok "Downloaded $model"
}

case "$MODEL_CHOICE" in
    1)
        download_model "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
        ;;
    2)
        download_model "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"
        download_model "Qwen/Qwen3-TTS-12Hz-1.7B-Base"
        download_model "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
        ;;
    3)
        info "Skipping model download."
        ;;
    *)
        warn "Invalid choice, skipping model download."
        ;;
esac

# --- Write docker-compose.yml ---
info "Writing docker-compose.yml..."

# Determine HF cache mount - handle both standard and hfhub symlink layouts
HF_CACHE="$HOME/.cache/huggingface"

cat > "$STACK_DIR/docker-compose.yml" <<YAML
services:
  qwen3-tts-api:
    image: qwen3-tts-api:latest
    container_name: qwen3-tts-api
    network_mode: host
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    volumes:
      - ${HF_CACHE}:/cache
      - cornfab-voices:/voices
    environment:
      - PORT=${QWEN3_PORT}
      - USE_FLASH_ATTENTION=false
      - LOCAL_FILES_ONLY=true
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${QWEN3_PORT}/health"]
      interval: 30s
      timeout: 30s
      start_period: 5m
      retries: 3

  cornfab:
    image: cornfab:latest
    container_name: cornfab
    network_mode: host
    volumes:
      - cornfab-voices:/root/.cornfab/voices
    environment:
      - TTS_API_BASE=http://localhost:${QWEN3_PORT}
    depends_on:
      qwen3-tts-api:
        condition: service_healthy
    restart: unless-stopped

volumes:
  cornfab-voices:
YAML

ok "docker-compose.yml written to $STACK_DIR/"

# --- Start ---
info "Starting stack..."
docker compose -f "$STACK_DIR/docker-compose.yml" up -d

echo ""
echo -e "${GREEN}${BOLD}  ╔═══════════════════════════════════════════╗"
echo "  ║             Setup complete                ║"
echo "  ╚═══════════════════════════════════════════╝${NC}"
echo ""
echo "  cornfab UI:      http://localhost:$CORNFAB_PORT"
echo "  qwen3-tts API:   http://localhost:$QWEN3_PORT"
echo ""
echo "  Manage:"
echo "    cd $STACK_DIR"
echo "    docker compose up -d      # start"
echo "    docker compose down       # stop"
echo "    docker compose logs -f    # logs"
echo ""
echo "  Note: qwen3-tts-api takes ~2-3 minutes to load models on first start."
echo "  Check health: curl http://localhost:$QWEN3_PORT/health"
echo ""
