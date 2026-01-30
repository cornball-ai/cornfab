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
  last_generation <- shiny::reactiveVal(NULL)

  # History state
  history <- shiny::reactiveVal(load_history())
  selected_entry <- shiny::reactiveVal(NULL)

  # Detect available backends
  available_backends <- detect_backends()
  default_backend <- unname(available_backends[1])

  # Update backend choices

  shiny::updateSelectInput(session, "backend",
    choices = available_backends,
    selected = default_backend)

  status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

  # Dynamic model selection based on backend
  output$model_section <- shiny::renderUI({
    backend <- input$backend
    if (is.null(backend)) backend <- default_backend

    models <- get_models_for_backend(backend)
    if (length(models$choices) > 0) {
      shiny::div(
        class = "settings-section",
        shiny::div(class = "section-title", "Model"),
        shiny::selectInput("model", NULL,
          choices = models$choices,
          selected = models$default,
          width = "100%")
      )
    }
  })

  # Dynamic voice selection based on backend
  output$voice_select <- shiny::renderUI({
    backend <- input$backend
    if (is.null(backend)) backend <- default_backend

    voices <- get_voices_for_backend(backend)
    shiny::selectInput("voice", NULL,
      choices = voices$choices,
      selected = voices$default,
      width = "100%")
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

  shiny::observeEvent(input$chatterbox_url, {
    if (input$backend == "chatterbox" && nzchar(input$chatterbox_url)) {
      tts.api::set_tts_base(input$chatterbox_url)
    }
  }, ignoreInit = TRUE)

  shiny::observeEvent(input$qwen3_url, {
    if (input$backend == "qwen3" && nzchar(input$qwen3_url)) {
      tts.api::set_tts_base(input$qwen3_url)
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
    last_generation(NULL)

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

      # Store generation info for history
      last_generation(list(
        text = text,
        voice = voice,
        backend = backend,
        model = model,
        format = format
      ))

      status_msg(sprintf("Done. Generated %s bytes of audio.", length(audio_bytes)))

      # Auto-save to history if enabled
      if (isTRUE(input$save_audio)) {
        save_to_history()
      }

    }, error = function(e) {
      status_msg(paste("Error:", conditionMessage(e)))
    })
  })

  # Save current generation to history
  save_to_history <- function() {
    gen <- last_generation()
    data <- audio_data()
    if (is.null(gen) || is.null(data)) return()

    entry <- create_history_entry(
      text = gen$text,
      voice = gen$voice,
      backend = gen$backend,
      model = gen$model
    )

    # Save audio file
    audio_path <- save_audio_file(data, entry$id, gen$format)
    entry$audio_file <- audio_path

    # Add to history
    new_history <- add_history_entry(history(), entry)
    history(new_history)
    save_history(new_history)
  }

  # Manual save to history button
  shiny::observeEvent(input$copy_to_history, {
    if (is.null(audio_data())) {
      status_msg("No audio to save.")
      return()
    }
    save_to_history()
    status_msg("Saved to history.")
  })

  # History list rendering
  output$history_list <- shiny::renderUI({
    hist <- history()
    sel <- selected_entry()

    if (length(hist) == 0) {
      return(shiny::div(
        class = "history-empty",
        "No generations yet"
      ))
    }

    items <- lapply(hist, function(entry) {
      is_selected <- !is.null(sel) && sel == entry$id

      shiny::div(
        class = paste("history-item", if (is_selected) "selected" else ""),
        `data-id` = entry$id,
        onclick = sprintf(
          "Shiny.setInputValue('history_click', '%s', {priority: 'event'})",
          entry$id
        ),
        shiny::div(
          class = "history-item-header",
          shiny::span(class = "history-timestamp", format_timestamp(entry$timestamp)),
          shiny::span(class = "history-backend", entry$backend),
          shiny::tags$button(
            class = "history-delete-btn",
            onclick = sprintf(
              "event.stopPropagation(); Shiny.setInputValue('history_delete', '%s', {priority: 'event'})",
              entry$id
            ),
            "x"
          )
        ),
        shiny::div(
          class = "history-preview",
          truncate_text(entry$text, 60)
        )
      )
    })

    shiny::tagList(items)
  })

  # Handle history item click
  shiny::observeEvent(input$history_click, {
    id <- input$history_click
    hist <- history()

    idx <- which(vapply(hist, function(e) e$id == id, logical(1)))
    if (length(idx) == 0) return()

    entry <- hist[[idx]]
    selected_entry(id)

    # Load audio if available
    if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
      audio_bytes <- readBin(entry$audio_file, "raw", file.info(entry$audio_file)$size)
      audio_data(audio_bytes)
      audio_file(entry$audio_file)

      # Update last_generation for potential re-save
      last_generation(list(
        text = entry$text,
        voice = entry$voice,
        backend = entry$backend,
        model = entry$model,
        format = tools::file_ext(entry$audio_file)
      ))
    }

    # Update text input
    shiny::updateTextAreaInput(session, "text_input", value = entry$text)

    status_msg(sprintf("Loaded: %s", format_timestamp(entry$timestamp)))
  })

  # Handle history delete
  shiny::observeEvent(input$history_delete, {
    id <- input$history_delete

    updated <- delete_history_entry(history(), id)
    history(updated)
    save_history(updated)

    if (!is.null(selected_entry()) && selected_entry() == id) {
      selected_entry(NULL)
      audio_data(NULL)
      audio_file(NULL)
    }

    status_msg("Entry deleted.")
  })

  # Clear all history
  shiny::observeEvent(input$clear_history, {
    hist <- history()
    # Delete all audio files
    for (entry in hist) {
      if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
        unlink(entry$audio_file)
      }
    }
    history(list())
    save_history(list())
    selected_entry(NULL)
    status_msg("History cleared.")
  })

  # Header status output
  output$header_status <- shiny::renderText({
    status_msg()
  })

  # Character count
  output$char_count <- shiny::renderText({
    text <- input$text_input
    if (is.null(text)) return("0 chars")
    sprintf("%d chars", nchar(text))
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

    # Determine MIME type from file extension or format
    file <- audio_file()
    if (!is.null(file)) {
      ext <- tools::file_ext(file)
    } else {
      ext <- input$output_format
    }

    if (ext == "mp3") {
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

  # Generation details
  output$generation_details <- shiny::renderText({
    gen <- last_generation()
    if (is.null(gen)) return("No generation yet.")

    paste0(
      "Backend: ", gen$backend, "\n",
      "Voice: ", gen$voice, "\n",
      if (!is.null(gen$model) && nzchar(gen$model)) paste0("Model: ", gen$model, "\n") else "",
      "Format: ", gen$format
    )
  })

  # Generated text display
  output$generated_text <- shiny::renderText({
    gen <- last_generation()
    if (is.null(gen)) return("")
    gen$text
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

  # Check for native chatterbox R package
  if (requireNamespace("chatterbox", quietly = TRUE)) {
    backends <- c(backends, "Chatterbox (native)" = "native")
  }

  # Check for Chatterbox container (port 7810)
  backends <- c(backends, "Chatterbox (container)" = "chatterbox")

  # Check for Qwen3-TTS (port 7811)
  qwen3_available <- tryCatch({
    tts.api::qwen3_available()
  }, error = function(e) FALSE)

  if (qwen3_available) {
    backends <- c(backends, "Qwen3-TTS" = "qwen3")
  } else {
    # Still add it as option, user can configure URL
    backends <- c(backends, "Qwen3-TTS" = "qwen3")
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
  if (nzchar(Sys.getenv("FAL_KEY", "")) &&
      requireNamespace("fal.api", quietly = TRUE)) {
    backends <- c(backends, "fal.ai" = "fal")
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
    base <- Sys.getenv("TTS_API_BASE", "http://localhost:7810")
    tts.api::set_tts_base(base)
  } else if (backend == "native") {
    # Native chatterbox - no API configuration needed
    # Model loads in R process
  } else if (backend == "qwen3") {
    base <- Sys.getenv("QWEN3_TTS_BASE", "http://localhost:7811")
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
  } else if (backend == "qwen3") {
    list(
      choices = c(
        "Qwen3-TTS 1.7B" = "Qwen/Qwen3-TTS",
        "Qwen3-TTS 0.6B" = "Qwen/Qwen3-TTS-0.6B"
      ),
      default = "Qwen/Qwen3-TTS"
    )
  } else {
    # Chatterbox (native and container) doesn't need model selection
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
    list(
      choices = c("Default" = "default"),
      default = "default"
    )
  } else if (backend == "qwen3") {
    # Qwen3-TTS built-in voices
    list(
      choices = c(
        "Vivian" = "Vivian",
        "Serena" = "Serena",
        "Uncle Fu" = "Uncle_Fu",
        "Dylan" = "Dylan",
        "Eric" = "Eric",
        "Ryan" = "Ryan",
        "Aiden" = "Aiden",
        "Ono Anna" = "Ono_Anna",
        "Sohee" = "Sohee"
      ),
      default = "Vivian"
    )
  } else if (backend == "chatterbox") {
    # Try to fetch voices from Chatterbox container
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
  } else if (backend == "native") {
    # Native chatterbox uses reference audio file
    list(
      choices = c("Reference file" = "reference"),
      default = "reference"
    )
  } else {
    list(
      choices = c("Default" = "default"),
      default = "default"
    )
  }
}
