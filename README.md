# cornfab

![cornfab](https://raw.githubusercontent.com/cornball-ai/cornfab/refs/heads/main/inst/app/www/cornfab.jpeg)

Text-to-speech Shiny app for the Cornball AI ecosystem.

## Features

- **Multi-backend TTS**: Chatterbox, Qwen3-TTS, OpenAI, ElevenLabs, fal.ai
- **Voice selection**: 9 built-in Qwen3 voices, OpenAI voices, ElevenLabs library
- **Voice cloning**: Upload reference audio for Chatterbox/Qwen3 backends
- **Voice design**: Create custom voices from natural language descriptions (Qwen3)
- **Save as voice**: Save generated audio as a reusable voice for cloning
- **History**: Persistent storage with audio playback in `~/.cornfab/`

## Installation

```r
# Install from GitHub
remotes::install_github("cornball-ai/cornfab")
```

## Usage

```r
library(cornfab)
run_app()  # Runs on port 7803
```

## Backends

| Backend | Type | Port | Features |
|---------|------|------|----------|
| Chatterbox | Container | 7810 | Voice cloning, exaggeration control |
| Qwen3-TTS | Container | 7811 | 9 voices, voice design, 10 languages |
| OpenAI | API | - | 6 voices, tts-1/tts-1-hd models |
| ElevenLabs | API | - | Large voice library, multilingual |
| fal.ai | API | - | F5-TTS, Dia, Orpheus models |

### Container Setup

Chatterbox and Qwen3-TTS run as local Docker containers. You must:
1. **Download models** before running containers
2. **Start containers manually** - cornfab does not auto-start containers

#### Model Storage

Models are stored in the HuggingFace cache:
```
~/.cache/huggingface/hub/
```

Mount this directory when running containers:
```bash
-v ~/.cache/huggingface:/root/.cache/huggingface
```

### Downloading Models

#### Chatterbox

Model: `ResembleAI/chatterbox` (~2GB)

**Option 1: R with hfhub (recommended)**
```r
# install.packages("hfhub")
hfhub::hub_snapshot("ResembleAI/chatterbox")
```

**Option 2: Python with huggingface_hub**
```bash
pip install huggingface_hub
python -c "from huggingface_hub import snapshot_download; snapshot_download('ResembleAI/chatterbox')"
```

**Option 3: curl**
```bash
mkdir -p ~/.cache/huggingface/hub/models--ResembleAI--chatterbox/snapshots/main
cd ~/.cache/huggingface/hub/models--ResembleAI--chatterbox/snapshots/main
curl -LO https://huggingface.co/ResembleAI/chatterbox/resolve/main/chatterbox.safetensors
curl -LO https://huggingface.co/ResembleAI/chatterbox/resolve/main/s3gen.safetensors
curl -LO https://huggingface.co/ResembleAI/chatterbox/resolve/main/t3_cfg.safetensors
curl -LO https://huggingface.co/ResembleAI/chatterbox/resolve/main/ve.safetensors
```

#### Qwen3-TTS

Three models are needed for full functionality:
- `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` - Built-in speakers (~7GB)
- `Qwen/Qwen3-TTS-12Hz-1.7B-Base` - Voice cloning (~7GB)
- `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` - Voice design (~7GB)

**Option 1: R with hfhub (recommended)**
```r
# Download all three models
hfhub::hub_snapshot("Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
hfhub::hub_snapshot("Qwen/Qwen3-TTS-12Hz-1.7B-Base")
hfhub::hub_snapshot("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign")
```

**Option 2: Python with huggingface_hub**
```bash
python -c "from huggingface_hub import snapshot_download; \
  snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice'); \
  snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-Base'); \
  snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign')"
```

**Option 3: Git LFS**
```bash
cd ~/.cache/huggingface/hub
git lfs install
git clone https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice
```

### Running Containers

**Note:** Containers default to `LOCAL_FILES_ONLY=true` and will fail if models aren't pre-downloaded. Set `LOCAL_FILES_ONLY=false` to enable auto-download (not recommended for production).

#### Chatterbox (port 7810)

```bash
# Build (if not using ghcr.io)
cd ~/chatterbox-tts-api
docker build -f docker/Dockerfile -t chatterbox-tts-api .

# Run
docker run -d --gpus all --network=host --name chatterbox \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -e PORT=7810 \
  chatterbox-tts-api
```

#### Qwen3-TTS (port 7811)

```bash
# Build (if not using ghcr.io)
cd ~/qwen3-tts-api
docker build -f Dockerfile.blackwell -t qwen3-tts-api:blackwell .

# Run (Blackwell GPUs - RTX 50xx)
docker run -d --gpus all --network=host --name qwen3-tts-api \
  -v ~/.cache/huggingface:/cache \
  -e PORT=7811 \
  -e USE_FLASH_ATTENTION=false \
  qwen3-tts-api:blackwell

# Run (older GPUs - Ampere, Ada Lovelace)
docker build -t qwen3-tts-api .  # Use default Dockerfile
docker run -d --gpus all --network=host --name qwen3-tts-api \
  -v ~/.cache/huggingface:/cache \
  -e PORT=7811 \
  qwen3-tts-api
```

### API Backends

For OpenAI, ElevenLabs, and fal.ai, set environment variables:

```bash
export OPENAI_API_KEY="sk-..."
export ELEVENLABS_API_KEY="..."
export FAL_KEY="..."
```

Or configure in the app's API Settings panel.

## Voice Design (Qwen3-TTS)

Qwen3-TTS supports creating custom voices from natural language descriptions.

### VRAM Usage

| Mode | Models Loaded | VRAM |
|------|---------------|------|
| Built-in voices | Base | ~4.6GB |
| Voice cloning | + CustomVoice | +4.1GB |
| Voice design | + VoiceDesign | +3.9GB |

Models load on first use and stay in memory. Restart the container to unload.

### Recommended Workflow

To avoid keeping the VoiceDesign model loaded:

1. **Design once**: Check "Design voice from description", enter a description like "A warm, friendly female voice with a slight British accent", generate
2. **Save as voice**: Click "Save as Voice", enter a name (e.g., "warm-female")
3. **Restart container**: `docker restart qwen3-tts-api` to free ~5GB VRAM
4. **Clone from saved**: Select "warm-female (custom)" from the voice dropdown for future generations

Saved voices are stored in `~/.cornfab/voices/` and work with both Qwen3 and Chatterbox backends.

## Development

```bash
# Clone
git clone https://github.com/cornball-ai/cornfab
cd cornfab

# Build and run
r -e 'tinyrox::document(); tinypkgr::install()'
r -e 'library(cornfab); run_app()'
```

## Related

- [tts.api](https://github.com/cornball-ai/tts.api) - R package for TTS APIs
- [earshot](https://github.com/cornball-ai/earshot) - Speech-to-text Shiny app
