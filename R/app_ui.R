#' App UI
#'
#' Create the Cornfab Shiny app user interface.
#'
#' @return A Shiny UI object.
#'
#' @keywords internal
app_ui <- function() {
  # Resource path for assets
  www_path <- system.file("app/www", package = "cornfab")
  if (www_path == "") {
    # Dev mode - use local path
    www_path <- "inst/app/www"
  }
  shiny::addResourcePath("www", www_path)

  bslib::page_fillable(
    theme = bslib::bs_theme(
      version = 5,
      primary = "#6366f1",
      "enable-rounded" = TRUE
    ),
    title = "cornfab",
    padding = 0,

    shiny::tags$head(
      shiny::tags$link(
        rel = "stylesheet",
        type = "text/css",
        href = "www/styles.css"
      ),
      shiny::tags$link(
        rel = "preconnect",
        href = "https://fonts.googleapis.com"
      ),
      shiny::tags$link(
        rel = "stylesheet",
        href = paste0(
          "https://fonts.googleapis.com/css2?",
          "family=Inter:wght@400;500;600&",
          "family=JetBrains+Mono&display=swap"
        )
      )
    ),

    # Header
    shiny::div(
      class = "cornfab-header",
      shiny::div(
        class = "header-content",
        shiny::tags$a(
          href = "https://cornball.ai",
          target = "_blank",
          class = "header-link",
          shiny::tags$img(src = "www/logo.png", class = "header-logo"),
          shiny::span("cornfab", class = "header-title")
        ),
        shiny::div(class = "header-spacer"),
        shiny::div(
          class = "header-status",
          shiny::textOutput("header_status", inline = TRUE)
        )
      )
    ),

    # Main layout
    shiny::div(
      class = "main-container",

      # Left sidebar - History
      shiny::div(
        class = "left-sidebar",
        shiny::div(
          class = "sidebar-header",
          shiny::span("History"),
          shiny::actionButton(
            "clear_history",
            "",
            icon = shiny::icon("trash"),
            class = "btn-icon btn-sm"
          )
        ),
        shiny::div(
          class = "sidebar-options",
          shiny::checkboxInput(
            "save_audio",
            "Save audio files",
            value = TRUE
          )
        ),
        shiny::div(
          class = "history-list",
          shiny::uiOutput("history_list")
        )
      ),

      # Center content
      shiny::div(
        class = "center-content",

        # Input panel
        shiny::div(
          class = "input-panel",
          shiny::div(
            class = "panel-header",
            shiny::span("Text Input"),
            shiny::span(
              class = "char-count",
              shiny::textOutput("char_count", inline = TRUE)
            )
          ),
          shiny::div(
            class = "text-input-wrapper",
            shiny::tags$textarea(
              id = "text_input",
              class = "form-control text-input",
              placeholder = "Enter text to convert to speech...",
              rows = 8
            )
          ),
          shiny::div(
            class = "input-controls",
            shiny::div(
              class = "voice-clone-section",
              shiny::fileInput(
                "voice_reference",
                NULL,
                accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac"),
                placeholder = "Voice reference (optional)",
                width = "100%"
              )
            ),
            shiny::actionButton(
              "generate",
              "Generate Speech",
              icon = shiny::icon("play"),
              class = "btn-generate"
            )
          )
        ),

        # Output panel
        shiny::div(
          class = "output-panel",
          shiny::div(
            class = "panel-header",
            shiny::span("Generated Audio")
          ),
          shiny::div(
            class = "audio-container",
            shiny::uiOutput("audio_player")
          ),
          shiny::div(
            class = "output-controls",
            shiny::downloadButton(
              "download_audio",
              "Download",
              class = "btn-download"
            ),
            shiny::actionButton(
              "copy_to_history",
              "Save to History",
              icon = shiny::icon("bookmark"),
              class = "btn-secondary"
            )
          ),
          # Tabs for details
          bslib::navset_underline(
            id = "output_tabs",
            bslib::nav_panel(
              "Details",
              shiny::div(
                class = "details-content",
                shiny::verbatimTextOutput("generation_details")
              )
            ),
            bslib::nav_panel(
              "Text",
              shiny::div(
                class = "text-content",
                shiny::verbatimTextOutput("generated_text")
              )
            )
          )
        )
      ),

      # Right sidebar - Settings
      shiny::div(
        class = "right-sidebar",

        # Backend section
        shiny::div(
          class = "settings-section",
          shiny::div(class = "section-title", "Backend"),
          shiny::selectInput(
            "backend",
            NULL,
            choices = c("Chatterbox" = "chatterbox"),
            selected = "chatterbox",
            width = "100%"
          ),
          shiny::uiOutput("backend_status")
        ),

        # Voice section
        shiny::div(
          class = "settings-section",
          shiny::div(
            class = "section-title-row",
            shiny::span("Voice", class = "section-title"),
            shiny::actionButton(
              "refresh_voices",
              "",
              icon = shiny::icon("refresh"),
              class = "btn-icon btn-sm"
            )
          ),
          shiny::uiOutput("voice_select")
        ),

        # Model section (conditional)
        shiny::uiOutput("model_section"),

        # Parameters section
        shiny::div(
          class = "settings-section",
          shiny::tags$details(
            class = "params-details",
            open = NA,
            shiny::tags$summary("Parameters"),
            shiny::div(
              class = "params-content",
              shiny::sliderInput(
                "speed",
                "Speed",
                min = 0.5,
                max = 2.0,
                value = 1.0,
                step = 0.1,
                width = "100%"
              ),
              # Chatterbox-specific
              shiny::conditionalPanel(
                condition = "input.backend == 'chatterbox' || input.backend == 'native'",
                shiny::sliderInput(
                  "exaggeration",
                  "Exaggeration",
                  min = 0,
                  max = 1,
                  value = 0.5,
                  step = 0.05,
                  width = "100%"
                ),
                shiny::sliderInput(
                  "cfg_weight",
                  "CFG Weight",
                  min = 0,
                  max = 1,
                  value = 0.5,
                  step = 0.05,
                  width = "100%"
                )
              ),
              # ElevenLabs-specific
              shiny::conditionalPanel(
                condition = "input.backend == 'elevenlabs'",
                shiny::sliderInput(
                  "stability",
                  "Stability",
                  min = 0,
                  max = 1,
                  value = 0.5,
                  step = 0.05,
                  width = "100%"
                ),
                shiny::sliderInput(
                  "similarity",
                  "Similarity Boost",
                  min = 0,
                  max = 1,
                  value = 0.75,
                  step = 0.05,
                  width = "100%"
                )
              ),
              shiny::numericInput(
                "seed",
                "Seed (optional)",
                value = NA,
                width = "100%"
              )
            )
          )
        ),

        # API Settings section
        shiny::div(
          class = "settings-section",
          shiny::tags$details(
            class = "api-details",
            shiny::tags$summary("API Settings"),
            shiny::div(
              class = "api-content",
              # Chatterbox URL
              shiny::conditionalPanel(
                condition = "input.backend == 'chatterbox'",
                shiny::textInput(
                  "chatterbox_url",
                  "Chatterbox URL",
                  value = Sys.getenv(
                    "TTS_API_BASE",
                    "http://localhost:4123"
                  ),
                  width = "100%"
                )
              ),
              # OpenAI key
              shiny::conditionalPanel(
                condition = "input.backend == 'openai'",
                shiny::passwordInput(
                  "openai_key",
                  "OpenAI API Key",
                  value = Sys.getenv("OPENAI_API_KEY", ""),
                  width = "100%"
                )
              ),
              # ElevenLabs key
              shiny::conditionalPanel(
                condition = "input.backend == 'elevenlabs'",
                shiny::passwordInput(
                  "elevenlabs_key",
                  "ElevenLabs API Key",
                  value = Sys.getenv("ELEVENLABS_API_KEY", ""),
                  width = "100%"
                )
              ),
              # fal.ai key
              shiny::conditionalPanel(
                condition = "input.backend == 'fal'",
                shiny::passwordInput(
                  "fal_key",
                  "fal.ai API Key",
                  value = Sys.getenv("FAL_KEY", ""),
                  width = "100%"
                )
              )
            )
          )
        ),

        # Output format
        shiny::div(
          class = "settings-section",
          shiny::div(class = "section-title", "Output Format"),
          shiny::selectInput(
            "output_format",
            NULL,
            choices = c("WAV" = "wav", "MP3" = "mp3"),
            selected = "wav",
            width = "100%"
          )
        )
      )
    )
  )
}
