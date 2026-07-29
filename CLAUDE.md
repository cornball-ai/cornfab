# cornfab

Text-to-speech app using tts.api, built on
[glinty](https://github.com/cornball-ai/glinty).

## Architecture

```
cornfab/
├── app.R              # RStudio "Run App" entrypoint
├── R/
│   ├── run_app.R      # Exported app launcher
│   ├── app_ui.R       # glinty UI tree
│   ├── app_server.R   # Reactive server logic
│   ├── icons.R        # Local inline-SVG icon set
│   └── history.R      # History persistence
└── inst/
    ├── app/www/       # styles.css, logo.png (served at /static/)
    ├── audio/         # jfk.wav reference clip
    └── tinytest/      # Tests
```

## Usage

**RStudio**: Click "Run App" button (uses `app.R`)

**From R**:
```r
library(cornfab)
run_app()  # port 7803
```

glinty listens on all interfaces, so treat the port as reachable from
the local network. There is no `host` argument; scope it with a
firewall or a reverse proxy.

## Features

- **Multi-backend support**:
  - Chatterbox (local, port 7810)
  - Qwen3-TTS (local, port 7811) - multilingual, voice cloning, voice design
  - OpenAI TTS
  - ElevenLabs

- **Voice selection**: Dynamic per backend (built-in voices, uploaded references)
- **History**: Persistent storage in `~/.cornfab/` with audio files
- **Parameters**: Speed, exaggeration, CFG weight, stability (backend-specific)

## Backends

| Backend | Port | Env Var | Features |
|---------|------|---------|----------|
| Chatterbox | 7810 | `TTS_API_BASE` | Voice cloning, exaggeration |
| Qwen3-TTS | 7811 | `QWEN3_TTS_BASE` | 9 voices, 10 languages, voice design |
| OpenAI | - | `OPENAI_API_KEY` | 11 voices, tts-1/tts-1-hd |
| ElevenLabs | - | `ELEVENLABS_API_KEY` | Many voices, multilingual |

## Qwen3-TTS Voices

Built-in voices: Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee

## Coming from the Shiny version

Migrated at 0.2.0. The differences that bite:

- Inputs are **called**: `input$backend()`, not `input$backend`.
- Inputs are `NULL` until set, and anything created inside
  `render_ui()` stays `NULL` until the user touches it. Optional reads
  go through `opt_str()` / `opt_num()` rather than bare `nzchar()`,
  which errors on `NULL`.
- All 11 `conditionalPanel`s became `conditional_panel()` with
  condition objects (`input_is`, `cond_and`, `cond_not`). No JS
  expression, no eval. Crucially these only toggle `display`, so the
  parameter sliders keep their values across a backend switch —
  `render_ui()` would reset them.
- History rows carry their own id on a click bind instead of inline
  `onclick` strings. The nearest bind wins, so the delete button
  inside a row does not also trigger the row.
- `shiny::icon()` is gone. `R/icons.R` has a local seven-shape inline
  SVG set; glinty deliberately ships no icons.
- The main textarea and the voice-description box were raw
  `tags$textarea` relying on Shiny's auto-binding; they are
  `textarea_input()` now.

## Secrets

**API key fields are deliberately not prefilled.** A `value=`
attribute is rendered into the page source in plain text, where
`type="password"` hides nothing, and the port is LAN-reachable.
`configure_backend()` reads `OPENAI_API_KEY` and `ELEVENLABS_API_KEY`
server-side; the fields exist only to override them, and empty means
"use the environment".

Do not reintroduce `value = Sys.getenv(...)` on a password field.
`inst/tinytest/test_server_wiring.R` asserts neither key appears in
the rendered page.

## Development

```bash
# Build, document, install, test
r -e 'rformat::rformat_dir("R", control_braces = "multi", expand_if = TRUE); tinyrox::document(); tinypkgr::install(); tinytest::test_package("cornfab")'

# Run without installing
r -e 'pkgload::load_all(); run_app()'
```

## History Storage

- Location: `~/.cornfab/` (symlinked to `~/.cornball/`)
- History file: `~/.cornfab/history.rds`
- Audio files: `~/.cornfab/audio/`
- Voices: `~/.cornfab/voices/` (via `voices_dir()` in `R/app_server.R`)

## TODO

- **Migrate storage to `~/.cornball/`** (breaking change):
  - Make base directory configurable (env var or parameter to `run_app()`)
  - Make history filename configurable (default: `~/.cornball/history/cornfab.rds`)
  - Update `history_dir()` and `audio_dir()` in `R/history.R`
  - Update `voices_dir()` in `R/app_server.R` (the migration collapsed
    the 5 hardcoded paths into that one helper, so this is now a
    one-line change)
  - Currently bridged via symlink: `~/.cornfab` -> `~/.cornball`
