#' App Server
#'
#' Server logic for the Cornfab Shiny app.
#'
#' @param input Shiny input object.
#' @param output Shiny output object.
#' @param session Shiny session object.
#'
#' @return NULL (side effects only).
#'
#' @keywords internal
app_server <- function(
  input,
  output,
  session
) {

  audio_data <- shiny::reactiveVal(NULL)
  audio_file <- shiny::reactiveVal(NULL)
  status_msg <- shiny::reactiveVal("Ready. Enter text and click Generate.")

  # Detect available backends
  available_backends <- detect_backends()
  default_backend <- unname(available_backends[1])

  # Update backend choices
  shiny::updateSelectInput(session, "backend",
    choices = available_backends,
    selected = default_backend)

  status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

  # Dynamic model selection based on backend
  output$model_select <- shiny::renderUI({
      backend <- input$backend
      if (is.null(backend)) backend <- default_backend

      models <- get_models_for_backend(backend)
      if (length(models$choices) > 0) {
        shiny::selectInput("model", "Model",
          choices = models$choices,
          selected = models$default)
      }
    })

  # Dynamic voice selection based on backend
  output$voice_select <- shiny::renderUI({
      backend <- input$backend
      if (is.null(backend)) backend <- default_backend

      voices <- get_voices_for_backend(backend)
      shiny::selectInput("voice", "Voice",
        choices = voices$choices,
        selected = voices$default)
    })

  # Configure backend when changed
  shiny::observeEvent(input$backend, {
      configure_backend(input$backend, input, session)
      status_msg(paste0("Backend: ", input$backend))
    }, ignoreInit = TRUE)

  # Apply API keys when changed
  shiny::observeEvent(input$openai_key, {
      if (input$backend == "openai" && nzchar(input$openai_key)) {
        tts.api::set_tts_key(input$openai_key)
      }
    }, ignoreInit = TRUE)

  shiny::observeEvent(input$elevenlabs_key, {
      if (input$backend == "elevenlabs" && nzchar(input$elevenlabs_key)) {
        tts.api::set_elevenlabs_key(input$elevenlabs_key)
      }
    }, ignoreInit = TRUE)

  shiny::observeEvent(input$fal_key, {
      if (input$backend == "fal" && nzchar(input$fal_key)) {
        if (requireNamespace("fal.api", quietly = TRUE)) {
          fal.api::set_fal_key(input$fal_key)
        }
      }
    }, ignoreInit = TRUE)

  shiny::observeEvent(input$chatterbox_base, {
      if (input$backend == "chatterbox" && nzchar(input$chatterbox_base)) {
        tts.api::set_tts_base(input$chatterbox_base)
      }
    }, ignoreInit = TRUE)

  # Generate speech
  shiny::observeEvent(input$generate, {
      text <- input$text_input

      if (is.null(text) || !nzchar(trimws(text))) {
        status_msg("Please enter some text to convert to speech.")
        return()
      }

      status_msg("Generating speech...")
      audio_data(NULL)
      audio_file(NULL)

      tryCatch({
          # Build parameters
          voice <- input$voice
          backend <- input$backend
          model <- input$model
          format <- input$output_format

          # Create temp file
          tmp_file <- tempfile(fileext = paste0(".", format))

          # Build call parameters
          params <- list(
            input = text,
            voice = voice,
            file = tmp_file,
            backend = backend,
            response_format = format
          )

          # Add model if specified
          if (!is.null(model) && nzchar(model)) {
            params$model <- model
          }

          # Add speed if not default
          if (!is.null(input$speed) && input$speed != 1.0) {
            params$speed <- input$speed
          }

          # Add seed if specified
          if (!is.null(input$seed) && !is.na(input$seed)) {
            params$seed <- as.integer(input$seed)
          }

          # Backend-specific parameters
          if (backend == "chatterbox") {
            if (!is.null(input$exaggeration)) {
              params$exaggeration <- input$exaggeration
            }
            if (!is.null(input$cfg_weight)) {
              params$cfg_weight <- input$cfg_weight
            }
          } else if (backend == "elevenlabs") {
            if (!is.null(input$stability)) {
              params$stability <- input$stability
            }
            if (!is.null(input$similarity)) {
              params$similarity_boost <- input$similarity
            }
          }

          # Call speech function
          do.call(tts.api::speech, params)

          # Read the audio data
          audio_bytes <- readBin(tmp_file, "raw", file.info(tmp_file)$size)
          audio_data(audio_bytes)
          audio_file(tmp_file)

          status_msg(sprintf("Done. Generated %s bytes of audio.", length(audio_bytes)))

        }, error = function(e) {
          status_msg(paste("Error:", conditionMessage(e)))
        })
    })

  # Status output
  output$status <- shiny::renderText({
      status_msg()
    })

  # Audio player
  output$audio_player <- shiny::renderUI({
      data <- audio_data()
      if (is.null(data)) {
        return(shiny::div(
            class = "no-audio",
            shiny::p("No audio generated yet. Enter text and click Generate.")
          ))
      }

      # Determine MIME type
      format <- input$output_format
      if (format == "mp3") {
        mime_type <- "audio/mpeg"
      } else {
        mime_type <- "audio/wav"
      }

      # Encode as base64
      b64 <- jsonlite::base64_enc(data)
      data_uri <- paste0("data:", mime_type, ";base64,", b64)

      shiny::tags$audio(
        src = data_uri,
        controls = "controls",
        autoplay = "autoplay",
        style = "width: 100%;"
      )
    })

  # Download handler
  output$download_audio <- shiny::downloadHandler(
    filename = function() {
      format <- input$output_format
      paste0("cornfab_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".", format)
    },
    content = function(file) {
      data <- audio_data()
      if (!is.null(data)) {
        writeBin(data, file)
      }
    }
  )
}

# Detect available backends
detect_backends <- function() {
  backends <- c()

  # Check for Chatterbox server
  chatterbox_base <- Sys.getenv("TTS_API_BASE", "http://localhost:4123")
  if (nzchar(chatterbox_base)) {
    backends <- c(backends, "Chatterbox (local)" = "chatterbox")
  }

  # Check for OpenAI API key
  if (nzchar(Sys.getenv("OPENAI_API_KEY", ""))) {
    backends <- c(backends, "OpenAI TTS" = "openai")
  }

  # Check for ElevenLabs API key
  if (nzchar(Sys.getenv("ELEVENLABS_API_KEY", ""))) {
    backends <- c(backends, "ElevenLabs" = "elevenlabs")
  }

  # Check for fal.ai
  if (nzchar(Sys.getenv("FAL_KEY", "")) && requireNamespace("fal.api", quietly = TRUE)) {
    backends <- c(backends, "fal.ai" = "fal")
  }

  # Fallback
  if (length(backends) == 0) {
    backends <- c("Chatterbox (local)" = "chatterbox", "OpenAI TTS" = "openai")
  }

  backends
}

# Configure backend
configure_backend <- function(
  backend,
  input,
  session
) {
  if (backend == "openai") {
    tts.api::set_tts_base("https://api.openai.com")
    key <- Sys.getenv("OPENAI_API_KEY", "")
    if (nzchar(key)) {
      tts.api::set_tts_key(key)
    }
  } else if (backend == "chatterbox") {
    base <- Sys.getenv("TTS_API_BASE", "http://localhost:4123")
    tts.api::set_tts_base(base)
  } else if (backend == "elevenlabs") {
    key <- Sys.getenv("ELEVENLABS_API_KEY", "")
    if (nzchar(key)) {
      tts.api::set_elevenlabs_key(key)
    }
  } else if (backend == "fal") {
    key <- Sys.getenv("FAL_KEY", "")
    if (nzchar(key) && requireNamespace("fal.api", quietly = TRUE)) {
      fal.api::set_fal_key(key)
    }
  }
}

# Get models for backend
get_models_for_backend <- function(backend) {
  if (backend == "openai") {
    list(
      choices = c("tts-1" = "tts-1", "tts-1-hd" = "tts-1-hd"),
      default = "tts-1"
    )
  } else if (backend == "elevenlabs") {
    list(
      choices = c(
        "Multilingual v2" = "eleven_multilingual_v2",
        "Turbo v2.5" = "eleven_turbo_v2_5",
        "English v1" = "eleven_monolingual_v1"
      ),
      default = "eleven_multilingual_v2"
    )
  } else if (backend == "fal") {
    list(
      choices = c(
        "F5-TTS" = "fal-ai/f5-tts",
        "Dia TTS" = "fal-ai/dia-tts",
        "Orpheus TTS" = "fal-ai/orpheus-tts"
      ),
      default = "fal-ai/f5-tts"
    )
  } else {
    # Chatterbox doesn't need model selection
    list(choices = character(0), default = NULL)
  }
}

# Get voices for backend
get_voices_for_backend <- function(backend) {
  if (backend == "openai") {
    list(
      choices = c(
        "Alloy" = "alloy",
        "Echo" = "echo",
        "Fable" = "fable",
        "Onyx" = "onyx",
        "Nova" = "nova",
        "Shimmer" = "shimmer"
      ),
      default = "nova"
    )
  } else if (backend == "elevenlabs") {
    # Common ElevenLabs voice IDs
    list(
      choices = c(
        "Rachel" = "21m00Tcm4TlvDq8ikWAM",
        "Domi" = "AZnzlk1XvdvUeBnXmlld",
        "Bella" = "EXAVITQu4vr4xnSDxMaL",
        "Antoni" = "ErXwobaYiN019PkySvjV",
        "Elli" = "MF3mGyEYCl7XYWbV9V6O",
        "Josh" = "TxGEqnHWrfWFTfGW9XjX",
        "Arnold" = "VR6AewLTigWG4xSOukaG",
        "Adam" = "pNInz6obpgDQGcFmaJgB",
        "Sam" = "yoZ06aMxZJJ28mfd3POQ"
      ),
      default = "21m00Tcm4TlvDq8ikWAM"
    )
  } else if (backend == "fal") {
    # F5-TTS uses reference audio, not named voices
    list(
      choices = c("Default" = "default"),
      default = "default"
    )
  } else if (backend == "chatterbox") {
    # Try to fetch voices from Chatterbox server
    tryCatch({
        voices <- tts.api::voices()
        if (length(voices) > 0) {
          choices <- setNames(voices, voices)
          list(choices = choices, default = voices[1])
        } else {
          list(
            choices = c("Default" = "default"),
            default = "default"
          )
        }
      }, error = function(e) {
        list(
          choices = c("Default" = "default"),
          default = "default"
        )
      })
  } else {
    list(
      choices = c("Default" = "default"),
      default = "default"
    )
  }
}

