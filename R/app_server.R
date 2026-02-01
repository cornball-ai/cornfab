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

  # Pending voice upload (for qwen3 folder confirmation)
  pending_upload <- shiny::reactiveVal(NULL)

  # Handle voice upload - upload to library and refresh list
  shiny::observeEvent(input$voice_upload, {
    upload <- input$voice_upload
    if (is.null(upload)) return()

    backend <- input$backend
    if (!backend %in% c("chatterbox", "qwen3", "native")) return()

    # Get voice name from filename (without extension)
    voice_name <- tools::file_path_sans_ext(upload$name)

    output$upload_status <- shiny::renderUI({
      shiny::tags$small(
        class = "upload-status",
        paste("Uploading", voice_name, "...")
      )
    })

    # All backends use local voice storage (~/.cornfab/voices/)
    voices_dir <- file.path(Sys.getenv("HOME"), ".cornfab", "voices")

    if (!dir.exists(voices_dir)) {
      # Need to create folder - ask for confirmation
      pending_upload(list(
        datapath = upload$datapath,
        name = upload$name,
        voice_name = voice_name,
        backend = backend
      ))
      shiny::showModal(shiny::modalDialog(
        title = "Create Voice Folder",
        shiny::p(paste0(
          "Voice files will be stored in: ", voices_dir
        )),
        shiny::p("Create this folder?"),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton("confirm_create_folder", "Create", class = "btn-primary")
        )
      ))
    } else {
      # Folder exists, save directly
      save_local_voice(upload$datapath, voice_name, voices_dir, backend, output, session)
    }
  }, ignoreInit = TRUE)

  # Handle folder creation confirmation
shiny::observeEvent(input$confirm_create_folder, {
    shiny::removeModal()
    upload <- pending_upload()
    if (is.null(upload)) return()

    voices_dir <- file.path(Sys.getenv("HOME"), ".cornfab", "voices")
    dir.create(voices_dir, recursive = TRUE, showWarnings = FALSE)

    save_local_voice(upload$datapath, upload$voice_name, voices_dir, upload$backend, output, session)
    pending_upload(NULL)
  }, ignoreInit = TRUE)

  # Generate speech
  shiny::observeEvent(input$generate, {
    text <- input$text_input

    if (is.null(text) || !nzchar(trimws(text))) {
      status_msg("Please enter some text to convert to speech.")
      return()
    }

    backend <- input$backend

    # Show appropriate status message
    if (backend == "native") {
      status_msg("Loading model and generating speech (first run may take longer)...")
    } else {
      status_msg("Generating speech...")
    }

    audio_data(NULL)
    audio_file(NULL)
    last_generation(NULL)

    tryCatch({
      # Build parameters
      voice <- input$voice
      model <- input$model
      format <- input$output_format

      # Resolve custom voice to file path
      is_custom_voice <- grepl("^custom:", voice)
      if (is_custom_voice) {
        voice_name <- sub("^custom:", "", voice)
        voices_dir <- file.path(Sys.getenv("HOME"), ".cornfab", "voices")
        voice_files <- list.files(voices_dir, pattern = paste0("^", voice_name, "\\."),
                                  full.names = TRUE, ignore.case = TRUE)
        if (length(voice_files) == 0) {
          stop("Voice file not found: ", voice_name)
        }
        voice <- voice_files[1]  # Use the actual file path
      }

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
      } else if (backend == "qwen3") {
        if (!is.null(input$language) && input$language != "English") {
          params$language <- input$language
        }
        if (!is.null(input$instruct) && nzchar(input$instruct)) {
          params$instructions <- input$instruct
        }
      }

      # Handle voice design, custom voices, and backend-specific generation
      use_voice_design <- isTRUE(input$use_voice_design) && backend == "qwen3"
      voice_desc <- input$voice_description

      if (use_voice_design && !is.null(voice_desc) && nzchar(trimws(voice_desc))) {
        # Qwen3 voice design: generate voice from description
        design_params <- list(
          input = text,
          voice_description = voice_desc,
          file = tmp_file
        )
        if (!is.null(params$language)) design_params$language <- params$language

        do.call(tts.api::speech_design, design_params)
      } else if (is_custom_voice && backend == "qwen3") {
        # Qwen3 custom voice: use speech_clone with x_vector_only
        clone_params <- list(
          input = text,
          voice_file = voice,  # Already resolved to file path
          file = tmp_file,
          backend = "qwen3",
          x_vector_only = TRUE
        )
        if (!is.null(params$language)) clone_params$language <- params$language
        if (!is.null(params$speed)) clone_params$speed <- params$speed
        if (!is.null(params$seed)) clone_params$seed <- params$seed

        do.call(tts.api::speech_clone, clone_params)
      } else if (is_custom_voice && backend == "chatterbox") {
        # Chatterbox custom voice: use speech_clone
        clone_params <- list(
          input = text,
          voice_file = voice,  # Already resolved to file path
          file = tmp_file,
          backend = "chatterbox"
        )
        if (!is.null(params$exaggeration)) clone_params$exaggeration <- params$exaggeration
        if (!is.null(params$cfg_weight)) clone_params$cfg_weight <- params$cfg_weight
        if (!is.null(params$speed)) clone_params$speed <- params$speed
        if (!is.null(params$seed)) clone_params$seed <- params$seed

        do.call(tts.api::speech_clone, clone_params)
      } else {
        # Regular tts (including native with custom voice, which uses file path directly)
        do.call(tts.api::tts, params)
      }

      # Read the audio data
      audio_bytes <- readBin(tmp_file, "raw", file.info(tmp_file)$size)
      audio_data(audio_bytes)
      audio_file(tmp_file)

      # Store generation info for history
      last_generation(list(
        text = text,
        voice = if (use_voice_design) "(designed)" else voice,
        voice_description = if (use_voice_design) voice_desc else NULL,
        backend = backend,
        model = model,
        format = format,
        speed = input$speed,
        exaggeration = input$exaggeration,
        cfg_weight = input$cfg_weight,
        stability = input$stability,
        similarity = input$similarity,
        language = input$language,
        instruct = input$instruct,
        seed = input$seed
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

    # Build params list (only non-default values)
    params <- list()
    if (!is.null(gen$speed) && gen$speed != 1.0) params$speed <- gen$speed
    if (!is.null(gen$exaggeration)) params$exaggeration <- gen$exaggeration
    if (!is.null(gen$cfg_weight)) params$cfg_weight <- gen$cfg_weight
    if (!is.null(gen$stability)) params$stability <- gen$stability
    if (!is.null(gen$similarity)) params$similarity <- gen$similarity
    if (!is.null(gen$language) && gen$language != "English") params$language <- gen$language
    if (!is.null(gen$instruct) && nzchar(gen$instruct)) params$instruct <- gen$instruct
    if (!is.null(gen$voice_description) && nzchar(gen$voice_description)) {
      params$voice_description <- gen$voice_description
    }
    if (!is.null(gen$seed) && !is.na(gen$seed)) params$seed <- gen$seed

    entry <- create_history_entry(
      text = gen$text,
      voice = gen$voice,
      backend = gen$backend,
      model = gen$model,
      params = if (length(params) > 0) params else NULL
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

  # Save as voice button - show modal to get voice name
  shiny::observeEvent(input$save_as_voice, {
    if (is.null(audio_data())) {
      status_msg("No audio to save as voice.")
      return()
    }

    shiny::showModal(shiny::modalDialog(
      title = "Save as Voice",
      shiny::p("Save this audio as a reusable voice for cloning."),
      shiny::textInput(
        "new_voice_name",
        "Voice Name",
        placeholder = "e.g., warm-female, narrator"
      ),
      footer = shiny::tagList(
        shiny::modalButton("Cancel"),
        shiny::actionButton("confirm_save_voice", "Save", class = "btn-primary")
      )
    ))
  })

  # Confirm save as voice
  shiny::observeEvent(input$confirm_save_voice, {
    voice_name <- input$new_voice_name
    if (is.null(voice_name) || !nzchar(trimws(voice_name))) {
      status_msg("Please enter a voice name.")
      return()
    }

    # Sanitize name (alphanumeric, dash, underscore only)
    voice_name <- gsub("[^a-zA-Z0-9_-]", "_", trimws(voice_name))

    voices_dir <- file.path(Sys.getenv("HOME"), ".cornfab", "voices")
    if (!dir.exists(voices_dir)) {
      dir.create(voices_dir, recursive = TRUE, showWarnings = FALSE)
    }

    # Determine format from last generation or default to wav
    gen <- last_generation()
    ext <- if (!is.null(gen$format)) gen$format else "wav"
    dest_file <- file.path(voices_dir, paste0(voice_name, ".", ext))

    tryCatch({
      writeBin(audio_data(), dest_file)
      shiny::removeModal()
      status_msg(paste0("Saved voice: ", voice_name))

      # Refresh voice list for current backend
      backend <- input$backend
      if (backend %in% c("chatterbox", "qwen3", "native")) {
        voices_data <- get_voices_for_backend(backend)
        shiny::updateSelectInput(
          session,
          "voice",
          choices = voices_data$choices,
          selected = paste0("custom:", voice_name)
        )
      }
    }, error = function(e) {
      status_msg(paste("Error saving voice:", conditionMessage(e)))
    })
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
          shiny::span(class = "history-backend", backend_label(entry$backend)),
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
        ),
        # Show params if any
        if (!is.null(entry$params) && length(entry$params) > 0) {
          shiny::div(
            class = "history-params",
            paste(names(entry$params), "=", unlist(entry$params), collapse = ", ")
          )
        }
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
        voice_description = entry$params$voice_description,
        backend = entry$backend,
        model = entry$model,
        format = tools::file_ext(entry$audio_file),
        speed = entry$params$speed,
        exaggeration = entry$params$exaggeration,
        cfg_weight = entry$params$cfg_weight,
        stability = entry$params$stability,
        similarity = entry$params$similarity,
        language = entry$params$language,
        instruct = entry$params$instruct,
        seed = entry$params$seed
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

    # Build params string based on backend
    params_str <- ""
    backend <- gen$backend

    # Speed is common to most backends
    if (!is.null(gen$speed) && gen$speed != 1.0) {
      params_str <- paste0(params_str, "Speed: ", gen$speed, "\n")
    }

    # Backend-specific params
    if (backend %in% c("chatterbox", "native")) {
      if (!is.null(gen$exaggeration)) {
        params_str <- paste0(params_str, "Exaggeration: ", gen$exaggeration, "\n")
      }
      if (!is.null(gen$cfg_weight)) {
        params_str <- paste0(params_str, "CFG Weight: ", gen$cfg_weight, "\n")
      }
    } else if (backend == "elevenlabs") {
      if (!is.null(gen$stability)) {
        params_str <- paste0(params_str, "Stability: ", gen$stability, "\n")
      }
      if (!is.null(gen$similarity)) {
        params_str <- paste0(params_str, "Similarity: ", gen$similarity, "\n")
      }
    } else if (backend == "qwen3") {
      if (!is.null(gen$language) && gen$language != "English") {
        params_str <- paste0(params_str, "Language: ", gen$language, "\n")
      }
      if (!is.null(gen$instruct) && nzchar(gen$instruct)) {
        params_str <- paste0(params_str, "Instructions: ", gen$instruct, "\n")
      }
      if (!is.null(gen$voice_description) && nzchar(gen$voice_description)) {
        params_str <- paste0(params_str, "Voice Design: ", gen$voice_description, "\n")
      }
    }

    # Seed is common
    if (!is.null(gen$seed) && !is.na(gen$seed)) {
      params_str <- paste0(params_str, "Seed: ", gen$seed, "\n")
    }

    paste0(
      "Backend: ", backend_label(gen$backend), "\n",
      "Voice: ", gen$voice, "\n",
      if (!is.null(gen$model) && nzchar(gen$model)) paste0("Model: ", gen$model, "\n") else "",
      "Format: ", gen$format,
      if (nzchar(params_str)) paste0("\n\n", params_str) else ""
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

# Get display label for backend
backend_label <- function(backend) {
  labels <- c(
    chatterbox = "Chatterbox (container)",
    native = "Chatterbox (native)",
    qwen3 = "Qwen3-TTS (container)",
    openai = "OpenAI TTS",
    elevenlabs = "ElevenLabs"
  )
  if (backend %in% names(labels)) labels[[backend]] else backend
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
    backends <- c(backends, "Qwen3-TTS (container)" = "qwen3")
  } else {
    # Still add it as option, user can configure URL
    backends <- c(backends, "Qwen3-TTS (container)" = "qwen3")
  }

  # Check for OpenAI API key
  if (nzchar(Sys.getenv("OPENAI_API_KEY", ""))) {
    backends <- c(backends, "OpenAI TTS" = "openai")
  }

  # Check for ElevenLabs API key
  if (nzchar(Sys.getenv("ELEVENLABS_API_KEY", ""))) {
    backends <- c(backends, "ElevenLabs" = "elevenlabs")
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

# Save voice file locally (for qwen3, native, and chatterbox)
save_local_voice <- function(datapath, voice_name, voices_dir, backend, output, session) {
  # Determine extension from original file
  ext <- tolower(tools::file_ext(datapath))
  if (!nzchar(ext)) ext <- "wav"

  dest_file <- file.path(voices_dir, paste0(voice_name, ".", ext))

  tryCatch({
    file.copy(datapath, dest_file, overwrite = TRUE)

    output$upload_status <- shiny::renderUI({
      shiny::tags$small(
        class = "upload-status success",
        paste("Saved:", voice_name)
      )
    })

    # Refresh voice list
    voices_data <- get_voices_for_backend(backend)
    shiny::updateSelectInput(
      session,
      "voice",
      choices = voices_data$choices,
      selected = paste0("custom:", voice_name)
    )

  }, error = function(e) {
    output$upload_status <- shiny::renderUI({
      shiny::tags$small(
        class = "upload-status error",
        paste("Error:", conditionMessage(e))
      )
    })
  })
}

# Get local custom voices
get_local_voices <- function() {
  voices_dir <- file.path(Sys.getenv("HOME"), ".cornfab", "voices")
  if (!dir.exists(voices_dir)) return(character(0))

  files <- list.files(voices_dir, pattern = "\\.(wav|mp3|m4a|ogg|flac)$", ignore.case = TRUE)
  if (length(files) == 0) return(character(0))

  voice_names <- tools::file_path_sans_ext(files)
  stats::setNames(
    paste0("custom:", voice_names),
    paste0(voice_names, " (custom)")
  )
}

# Get voices for backend
get_voices_for_backend <- function(backend) {
  if (backend == "openai") {
    list(
      choices = c(
        "Alloy" = "alloy",
        "Ash" = "ash",
        "Ballad" = "ballad",
        "Coral" = "coral",
        "Echo" = "echo",
        "Fable" = "fable",
        "Nova" = "nova",
        "Onyx" = "onyx",
        "Sage" = "sage",
        "Shimmer" = "shimmer",
        "Verse" = "verse"
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
  } else if (backend == "qwen3") {
    # Qwen3-TTS built-in voices + local custom voices
    builtin <- c(
      "Vivian" = "Vivian",
      "Serena" = "Serena",
      "Uncle Fu" = "Uncle_Fu",
      "Dylan" = "Dylan",
      "Eric" = "Eric",
      "Ryan" = "Ryan",
      "Aiden" = "Aiden",
      "Ono Anna" = "Ono_Anna",
      "Sohee" = "Sohee"
    )
    custom <- get_local_voices()
    list(
      choices = c(builtin, custom),
      default = "Vivian"
    )
  } else if (backend == "chatterbox") {
    # Local custom voices (shared with other backends)
    custom <- get_local_voices()
    list(
      choices = c(custom, "Default" = "default"),
      default = if (length(custom) > 0) custom[1] else "default"
    )
  } else if (backend == "native") {
    # Native chatterbox: JFK sample + local custom voices
    jfk_path <- system.file("audio", "jfk.wav", package = "cornfab")
    builtin <- c("JFK Sample" = jfk_path)
    custom <- get_local_voices()
    list(
      choices = c(builtin, custom),
      default = jfk_path
    )
  } else {
    list(
      choices = c("Default" = "default"),
      default = "default"
    )
  }
}
