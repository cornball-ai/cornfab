# cornfab

Text-to-speech Shiny app using tts.api.

## Architecture

```
cornfab/
├── app.R              # RStudio "Run App" entrypoint
├── R/
│   ├── run_app.R      # Exported app launcher
│   ├── app_ui.R       # Shiny UI
│   ├── app_server.R   # Shiny server logic
│   └── history.R      # History persistence
└── inst/
    ├── app/www/       # Static assets (CSS, logo)
    └── tinytest/      # Tests
```

## Usage

**RStudio**: Click "Run App" button (uses `app.R`)

**From R**:
```r
library(cornfab)
run_app()  # port 7803
```

## Features

- **Multi-backend support**:
  - Chatterbox (local, port 7810)
  - Qwen3-TTS (local, port 7811) - multilingual, voice cloning, voice design
  - OpenAI TTS
  - ElevenLabs
  - fal.ai (F5-TTS, Dia, Orpheus)

- **Voice selection**: Dynamic per backend (built-in voices, uploaded references)
- **History**: Persistent storage in `~/.cornfab/` with audio files
- **Parameters**: Speed, exaggeration, CFG weight, stability (backend-specific)

## Backends

| Backend | Port | Env Var | Features |
|---------|------|---------|----------|
| Chatterbox | 7810 | `TTS_API_BASE` | Voice cloning, exaggeration |
| Qwen3-TTS | 7811 | `QWEN3_TTS_BASE` | 9 voices, 10 languages, voice design |
| OpenAI | - | `OPENAI_API_KEY` | 6 voices, tts-1/tts-1-hd |
| ElevenLabs | - | `ELEVENLABS_API_KEY` | Many voices, multilingual |
| fal.ai | - | `FAL_KEY` | F5-TTS, Dia, Orpheus |

## Qwen3-TTS Voices

Built-in voices: Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee

## Development

```bash
# Build and install
r -e 'tinyrox::document(); tinypkgr::install()'

# Run without installing
r -e 'tinypkgr::load_all(); run_app()'

# Test
r -e 'tinytest::test_package("cornfab")'
```

## History Storage

- Location: `~/.cornfab/` (symlinked to `~/.cornball/`)
- History file: `~/.cornfab/history.rds`
- Audio files: `~/.cornfab/audio/`

## TODO

- **Migrate storage to `~/.cornball/`** (breaking change):
  - Make base directory configurable (env var or parameter to `run_app()`)
  - Make history filename configurable (default: `~/.cornball/history/cornfab.rds`)
  - Update `history_dir()` and `audio_dir()` in `R/history.R`
  - Update voice discovery paths in `R/app_server.R` (5+ hardcoded `~/.cornfab/voices/` refs)
  - Currently bridged via symlink: `~/.cornfab` -> `~/.cornball`
