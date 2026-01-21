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
    theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
    title = "cornfab",

    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "www/styles.css")
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
        )
      )
    ),

    # Main layout with sidebar
    bslib::layout_sidebar(
      fillable = TRUE,
      sidebar = bslib::sidebar(
        width = 350,

        # Settings panel (collapsible)
        shiny::tags$details(
          class = "settings-panel",
          shiny::tags$summary("Settings"),
          shiny::div(
            class = "settings-content",
            shiny::selectInput("backend", "Backend",
              choices = c("Chatterbox" = "chatterbox"),
              selected = "chatterbox"),

            shiny::uiOutput("model_select"),

            shiny::conditionalPanel(
              condition = "input.backend == 'openai'",
              shiny::passwordInput("openai_key", "OpenAI API Key",
                value = Sys.getenv("OPENAI_API_KEY", ""))
            ),

            shiny::conditionalPanel(
              condition = "input.backend == 'elevenlabs'",
              shiny::passwordInput("elevenlabs_key", "ElevenLabs API Key",
                value = Sys.getenv("ELEVENLABS_API_KEY", ""))
            ),

            shiny::conditionalPanel(
              condition = "input.backend == 'fal'",
              shiny::passwordInput("fal_key", "fal.ai API Key",
                value = Sys.getenv("FAL_KEY", ""))
            ),

            shiny::conditionalPanel(
              condition = "input.backend == 'chatterbox'",
              shiny::textInput("chatterbox_base", "Chatterbox URL",
                value = Sys.getenv("TTS_API_BASE", "http://localhost:4123"))
            )
          )
        ),

        shiny::hr(),

        # Voice selection
        shiny::uiOutput("voice_select"),

        # Voice parameters (collapsible)
        shiny::tags$details(
          class = "voice-params",
          shiny::tags$summary("Voice Parameters"),
          shiny::div(
            class = "params-content",
            shiny::sliderInput("speed", "Speed", min = 0.5, max = 2.0,
              value = 1.0, step = 0.1),
            shiny::conditionalPanel(
              condition = "input.backend == 'chatterbox'",
              shiny::sliderInput("exaggeration", "Exaggeration", min = 0, max = 1,
                value = 0.5, step = 0.05),
              shiny::sliderInput("cfg_weight", "CFG Weight", min = 0, max = 1,
                value = 0.5, step = 0.05)
            ),
            shiny::conditionalPanel(
              condition = "input.backend == 'elevenlabs'",
              shiny::sliderInput("stability", "Stability", min = 0, max = 1,
                value = 0.5, step = 0.05),
              shiny::sliderInput("similarity", "Similarity Boost", min = 0, max = 1,
                value = 0.75, step = 0.05)
            ),
            shiny::numericInput("seed", "Seed (optional)", value = NA)
          )
        ),

        shiny::hr(),

        # Text input
        shiny::textAreaInput("text_input", "Text to Speak",
          placeholder = "Enter text to convert to speech...",
          rows = 5),

        # Output format
        shiny::selectInput("output_format", "Output Format",
          choices = c("WAV" = "wav", "MP3" = "mp3"),
          selected = "wav"),

        # Generate button
        shiny::actionButton("generate", "Generate Speech", class = "btn-primary w-100"),

        shiny::hr(),
        shiny::verbatimTextOutput("status")
      ),

      # Main content - audio player and download
      bslib::card(
        bslib::card_header("Generated Audio"),
        bslib::card_body(
          shiny::uiOutput("audio_player"),
          shiny::br(),
          shiny::downloadButton("download_audio", "Download Audio", class = "btn-success")
        )
      )
    )
  )
}

