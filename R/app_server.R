#' App Server
#'
#' Server logic for the Cornfab app.
#'
#' @param input glinty input proxy.
#' @param output glinty output proxy.
#' @param session glinty session.
#'
#' @return NULL (side effects only).
#'
#' @keywords internal
app_server <- function(input, output, session) {
    audio_data <- glinty::reactive_val(NULL)
    audio_file <- glinty::reactive_val(NULL)
    status_msg <- glinty::reactive_val("Ready. Enter text and click Generate.")
    last_generation <- glinty::reactive_val(NULL)
    voice_refresh <- glinty::reactive_val(0) # Triggers voice list refresh

    # History state
    history <- glinty::reactive_val(load_history())
    selected_entry <- glinty::reactive_val(NULL)

    # Detect available backends
    available_backends <- detect_backends()
    default_backend <- unname(available_backends[1])

    glinty::update_select_input(session, "backend",
                                choices = available_backends,
                                selected = default_backend)

    status_msg(paste0("Ready. Using ", names(available_backends)[1], "."))

    # Inputs are NULL until set, and inputs built inside render_ui() stay
    # NULL until touched, so every optional read goes through these.
    current_backend <- function() {
        opt_str(input$backend()) %||% default_backend
    }
    current_voice <- function() {
        opt_str(input$voice()) %||%
        get_voices_for_backend(current_backend())$default
    }
    current_model <- function() {
        opt_str(input$model()) %||%
        get_models_for_backend(current_backend())$default
    }

    # Dynamic model selection based on backend
    output$model_section <- glinty::render_ui(function() {
        models <- get_models_for_backend(current_backend())
        if (length(models$choices) == 0) {
            return(NULL)
        }
        glinty::panel(
                      variant = "sidebar", title = "Model",
                      glinty::select_input("model", "",
                choices = models$choices,
                selected = models$default)
        )
    })

    # Dynamic voice selection based on backend
    output$voice_select <- glinty::render_ui(function() {
        voice_refresh() # Dependency: refresh after upload or save
        voices <- get_voices_for_backend(current_backend())
        glinty::select_input("voice", "",
                             choices = voices$choices,
                             selected = voices$default)
    })

    glinty::observe_event(input$refresh_voices, function() {
        voice_refresh(voice_refresh() + 1)
        status_msg("Voice list refreshed.")
    })

    # Configure backend when changed
    glinty::observe_event(input$backend, function() {
        configure_backend(current_backend())
        status_msg(paste0("Backend: ", backend_label(current_backend())))
    })

    # Apply API settings when changed. Empty means "use the environment",
    # which configure_backend() already applied.
    glinty::observe_event(input$openai_key, function() {
        key <- opt_str(input$openai_key())
        if (identical(current_backend(), "openai") && !is.null(key)) {
            tts.api::set_tts_key(key)
        }
    })

    glinty::observe_event(input$elevenlabs_key, function() {
        key <- opt_str(input$elevenlabs_key())
        if (identical(current_backend(), "elevenlabs") && !is.null(key)) {
            tts.api::set_elevenlabs_key(key)
        }
    })

    glinty::observe_event(input$chatterbox_url, function() {
        url <- opt_str(input$chatterbox_url())
        if (identical(current_backend(), "chatterbox") && !is.null(url)) {
            tts.api::set_tts_base(url)
        }
    })

    glinty::observe_event(input$qwen3_url, function() {
        url <- opt_str(input$qwen3_url())
        if (identical(current_backend(), "qwen3") && !is.null(url)) {
            tts.api::set_tts_base(url)
        }
    })

    # Container controls -----------------------------------------------

    has_gpuctl <- requireNamespace("gpu.ctl", quietly = TRUE)

    container_running <- function(name) {
        if (has_gpuctl) {
            svc_name <- .cornfab_svc_name(name)
            return(svc_name %in% gpu.ctl::gpu_status()$active)
        }
        tryCatch({
            out <- system2("docker", c("inspect", "-f", "{{.State.Running}}", name),
                           stdout = TRUE, stderr = TRUE)
            identical(trimws(out), "true")
        }, error = function(e) FALSE)
    }

    get_vram_usage <- function() {
        if (has_gpuctl) {
            tryCatch({
                total <- gpu.ctl::gpu_get_vram()
                used <- gpu.ctl::gpu_used_vram()
                list(used = used * 1024, total = total * 1024)
            }, error = function(e) NULL)
        } else {
            # No GPU is the normal case on a laptop, and nvidia-smi warns
            # rather than erroring when it is missing or fails. Suppress
            # both paths and report "no VRAM info" instead of leaking
            # warnings into the console on every 5-second refresh.
            suppressWarnings(tryCatch({
                out <- system2("nvidia-smi",
                               c("--query-gpu=memory.used,memory.total",
                                 "--format=csv,noheader,nounits"),
                               stdout = TRUE, stderr = TRUE)
                parts <- strsplit(trimws(out[1]), ",\\s*")[[1]]
                used <- as.numeric(parts[1])
                total <- as.numeric(parts[2])
                if (length(used) != 1L || is.na(used) ||
                                      length(total) != 1L || is.na(total)) {
                    return(NULL)
                }
                list(used = used, total = total)
            }, error = function(e) NULL))
        }
    }

    # Both container panels are the same widget over a different service.
    container_panel <- function(container, ids) {
        glinty::render_ui(function() {
            glinty::invalidate_later(5000) # refresh status every 5s
            running <- container_running(container)
            vram <- get_vram_usage()

            controls <- if (running) {
                list(
                     glinty::button(ids$restart, "Restart", icon = "rotate",
                                    variant = "secondary"),
                     glinty::button(ids$stop, "Stop", icon = "stop",
                                    variant = "danger")
                )
            } else {
                list(glinty::button(ids$start, "Start Container",
                                    icon = "play"))
            }

            if (!is.null(vram)) {
                controls <- c(controls, list(glinty::txt(
                            sprintf("VRAM: %.1f / %.1f GB",
                                    vram$used / 1024, vram$total / 1024),
                            variant = "muted")))
            }

            do.call(glinty::column, c(controls, list(gap = 8L)))
        })
    }

    qwen3_ids <- list(start = "start_qwen3", stop = "stop_qwen3",
                      restart = "restart_qwen3")
    chatterbox_ids <- list(start = "start_chatterbox",
                           stop = "stop_chatterbox", restart = "restart_chatterbox")

    output$qwen3_container_btn <- container_panel("qwen3-tts-api", qwen3_ids)
    output$chatterbox_container_btn <- container_panel("chatterbox",
        chatterbox_ids)

    glinty::observe_event(input$stop_qwen3, function() {
        status_msg("Stopping qwen3-tts-api...")
        .cornfab_gpu_release("qwen3-tts-api", status_msg)
    })

    glinty::observe_event(input$start_qwen3, function() {
        status_msg("Starting qwen3-tts-api...")
        .cornfab_gpu_acquire("qwen3-tts-api", status_msg)
    })

    glinty::observe_event(input$restart_qwen3, function() {
        status_msg("Restarting qwen3-tts-api...")
        .cornfab_gpu_release("qwen3-tts-api", status_msg)
        .cornfab_gpu_acquire("qwen3-tts-api", status_msg)
    })

    glinty::observe_event(input$stop_chatterbox, function() {
        status_msg("Stopping chatterbox...")
        .cornfab_gpu_release("chatterbox", status_msg)
    })

    glinty::observe_event(input$start_chatterbox, function() {
        status_msg("Starting chatterbox...")
        .cornfab_gpu_acquire("chatterbox", status_msg)
    })

    glinty::observe_event(input$restart_chatterbox, function() {
        status_msg("Restarting chatterbox...")
        .cornfab_gpu_release("chatterbox", status_msg)
        .cornfab_gpu_acquire("chatterbox", status_msg)
    })

    # Voice upload -----------------------------------------------------

    pending_upload <- glinty::reactive_val(NULL)
    upload_status <- glinty::reactive_val(NULL)

    output$upload_status <- glinty::render_ui(function() {
        st <- upload_status()
        if (is.null(st)) {
            return(NULL)
        }
        # A component rather than plain text, because the outcome
        # changes how it reads: an error is emphasised, progress and
        # success are quiet. Colour was doing that job through a
        # class, which is a browser-only lever -- variant is the one
        # every frontend has.
        glinty::txt(st$text,
                    variant = if (identical(st$class, "error")) {
                "strong"
            } else {
                "muted"
            })
    })

    glinty::observe_event(input$voice_upload, function() {
        upload <- input$voice_upload()
        if (is.null(upload)) {
            return(invisible(NULL))
        }

        backend <- current_backend()
        if (!backend %in% c("chatterbox", "qwen3", "native")) {
            return(invisible(NULL))
        }

        voice_name <- tools::file_path_sans_ext(upload$name[[1]])
        upload_status(list(text = paste("Uploading", voice_name, "..."),
                           class = ""))

        voices_dir <- voices_dir()

        if (!dir.exists(voices_dir)) {
            # Need to create the folder - ask first
            pending_upload(list(
                                datapath = upload$datapath[[1]],
                                name = upload$name[[1]],
                                voice_name = voice_name,
                                backend = backend
                ))
            glinty::show_modal(
                               session,
                               glinty::txt(paste0("Voice files will be stored in: ", voices_dir)),
                               glinty::txt("Create this folder?"),
                               title = "Create Voice Folder",
                               footer = glinty::row(
                    glinty::modal_button("Cancel"),
                    glinty::button("confirm_create_folder", "Create")
                )
            )
        } else {
            save_local_voice(upload$datapath[[1]], voice_name, voices_dir)
        }
    })

    glinty::observe_event(input$confirm_create_folder, function() {
        glinty::remove_modal(session)
        upload <- pending_upload()
        if (is.null(upload)) {
            return(invisible(NULL))
        }

        dir.create(voices_dir(), recursive = TRUE, showWarnings = FALSE)
        save_local_voice(upload$datapath, upload$voice_name, voices_dir())
        pending_upload(NULL)
    })

    # Copies a voice file into the library and refreshes the picker.
    save_local_voice <- function(datapath, voice_name, dir) {
        ext <- tolower(tools::file_ext(datapath))
        if (!nzchar(ext)) {
            ext <- "wav"
        }
        dest_file <- file.path(dir, paste0(voice_name, ".", ext))

        tryCatch({
            file.copy(datapath, dest_file, overwrite = TRUE)
            upload_status(list(text = paste("Saved:", voice_name),
                               class = "success"))
            voice_refresh(voice_refresh() + 1)
            glinty::update_select_input(session, "voice",
                                        choices = get_voices_for_backend(current_backend())$choices,
                                        selected = paste0("custom:", voice_name))
        }, error = function(e) {
            upload_status(list(text = paste("Error:", conditionMessage(e)),
                               class = "error"))
        })
    }

    # Generate ---------------------------------------------------------

    glinty::observe_event(input$generate, function() {
        text <- opt_str(input$text_input())

        if (is.null(text) || !nzchar(trimws(text))) {
            status_msg("Please enter some text to convert to speech.")
            return(invisible(NULL))
        }

        backend <- current_backend()

        if (identical(backend, "native")) {
            status_msg(paste("Loading model and generating speech",
                             "(first run may take longer)..."))
        } else {
            status_msg("Generating speech...")
        }

        audio_data(NULL)
        audio_file(NULL)
        last_generation(NULL)

        glinty::with_progress(session, message = "Generating speech...", {
            glinty::inc_progress(0.1, detail = "Preparing")

            tryCatch({
                gen <- generate_speech(backend, text, input)
                glinty::inc_progress(0.7, detail = "Reading audio")

                audio_bytes <- readBin(gen$file, "raw",
                                       file.info(gen$file)$size)
                audio_data(audio_bytes)
                audio_file(gen$file)
                last_generation(gen$info)

                status_msg(sprintf("Done. Generated %s bytes of audio.",
                                   length(audio_bytes)))

                if (isTRUE(input$save_audio())) {
                    save_to_history()
                }
            }, error = function(e) {
                status_msg(paste("Error:", conditionMessage(e)))
            })
        })
    })

    # Builds the parameter set for the current backend and calls tts.api.
    # Returns list(file, info); the caller reads the bytes.
    generate_speech <- function(backend, text, input) {
        voice <- current_voice()
        model <- current_model()
        format <- opt_str(input$output_format()) %||% "wav"

        # Resolve a custom voice to its file path
        is_custom_voice <- grepl("^custom:", voice)
        if (is_custom_voice) {
            voice_name <- sub("^custom:", "", voice)
            voice_files <- list.files(voices_dir(),
                                      pattern = paste0("^", voice_name, "\\."),
                                      full.names = TRUE, ignore.case = TRUE)
            if (length(voice_files) == 0) {
                stop("Voice file not found: ", voice_name)
            }
            voice <- voice_files[1]
        }

        tmp_file <- tempfile(fileext = paste0(".", format))

        params <- list(
                       input = text,
                       voice = voice,
                       file = tmp_file,
                       backend = backend,
                       response_format = format
        )
        if (!is.null(model)) {
            params$model <- model
        }

        speed <- opt_num(input$speed())
        if (!is.null(speed) && speed != 1.0) {
            params$speed <- speed
        }
        seed <- opt_num(input$seed())
        if (!is.null(seed)) {
            params$seed <- as.integer(seed)
        }

        if (identical(backend, "chatterbox")) {
            params$exaggeration <- opt_num(input$exaggeration())
            params$cfg_weight <- opt_num(input$cfg_weight())
        } else if (identical(backend, "elevenlabs")) {
            params$stability <- opt_num(input$stability())
            params$similarity_boost <- opt_num(input$similarity())
        } else if (identical(backend, "qwen3")) {
            language <- opt_str(input$language())
            if (!is.null(language) && !identical(language, "English")) {
                params$language <- language
            }
            instruct <- opt_str(input$instruct())
            if (!is.null(instruct)) {
                params$instructions <- instruct
            }
        }
        params <- Filter(Negate(is.null), params)

        use_voice_design <- isTRUE(input$use_voice_design()) &&
        identical(backend, "qwen3")
        voice_desc <- opt_str(input$voice_description())

        if (use_voice_design && !is.null(voice_desc) &&
            nzchar(trimws(voice_desc))) {
            design_params <- list(input = text, voice_description = voice_desc,
                                  file = tmp_file)
            if (!is.null(params$language)) {
                design_params$language <- params$language
            }
            do.call(tts.api::speech_design, design_params)
        } else if (is_custom_voice && identical(backend, "qwen3")) {
            clone_params <- list(input = text, voice_file = voice, file = tmp_file,
                                 backend = "qwen3", x_vector_only = TRUE)
            for (nm in c("language", "speed", "seed")) {
                if (!is.null(params[[nm]])) {
                    clone_params[[nm]] <- params[[nm]]
                }
            }
            do.call(tts.api::speech_clone, clone_params)
        } else if (is_custom_voice && identical(backend, "chatterbox")) {
            clone_params <- list(input = text, voice_file = voice, file = tmp_file,
                                 backend = "chatterbox")
            for (nm in c("exaggeration", "cfg_weight", "speed", "seed")) {
                if (!is.null(params[[nm]])) {
                    clone_params[[nm]] <- params[[nm]]
                }
            }
            do.call(tts.api::speech_clone, clone_params)
        } else {
            do.call(tts.api::tts, params)
        }

        info <- list(
                     text = text,
                     voice = if (use_voice_design) "(designed)" else voice,
                     voice_description = if (use_voice_design) voice_desc else NULL,
                     backend = backend,
                     model = model,
                     format = format,
                     speed = opt_num(input$speed()),
                     exaggeration = opt_num(input$exaggeration()),
                     cfg_weight = opt_num(input$cfg_weight()),
                     stability = opt_num(input$stability()),
                     similarity = opt_num(input$similarity()),
                     language = opt_str(input$language()),
                     instruct = opt_str(input$instruct()),
                     seed = opt_num(input$seed())
        )

        list(file = tmp_file, info = info)
    }

    # History ----------------------------------------------------------

    save_to_history <- function() {
        gen <- last_generation()
        data <- audio_data()
        if (is.null(gen) || is.null(data)) {
            return(invisible(NULL))
        }

        params <- list()
        if (!is.null(gen$speed) && gen$speed != 1.0) {
            params$speed <- gen$speed
        }
        params$exaggeration <- gen$exaggeration
        params$cfg_weight <- gen$cfg_weight
        params$stability <- gen$stability
        params$similarity <- gen$similarity
        if (!is.null(gen$language) && !identical(gen$language, "English")) {
            params$language <- gen$language
        }
        params$instruct <- gen$instruct
        params$voice_description <- gen$voice_description
        params$seed <- gen$seed
        params <- Filter(Negate(is.null), params)

        entry <- create_history_entry(
                                      text = gen$text,
                                      voice = gen$voice,
                                      backend = gen$backend,
                                      model = gen$model,
                                      params = if (length(params) > 0) params else NULL
        )

        entry$audio_file <- save_audio_file(data, entry$id, gen$format)

        new_history <- add_history_entry(history(), entry)
        history(new_history)
        save_history(new_history)
    }

    glinty::observe_event(input$copy_to_history, function() {
        if (is.null(audio_data())) {
            status_msg("No audio to save.")
            return(invisible(NULL))
        }
        save_to_history()
        status_msg("Saved to history.")
    })

    # Save as voice ----------------------------------------------------

    glinty::observe_event(input$save_as_voice, function() {
        if (is.null(audio_data())) {
            status_msg("No audio to save as voice.")
            return(invisible(NULL))
        }

        glinty::show_modal(
                           session,
                           glinty::txt("Save this audio as a reusable voice for cloning."),
                           glinty::text_input("new_voice_name", "Voice Name",
                placeholder = "e.g., warm-female, narrator"),
                           title = "Save as Voice",
                           footer = glinty::row(
                glinty::modal_button("Cancel"),
                glinty::button("confirm_save_voice", "Save")
            )
        )
    })

    glinty::observe_event(input$confirm_save_voice, function() {
        voice_name <- opt_str(input$new_voice_name())
        if (is.null(voice_name) || !nzchar(trimws(voice_name))) {
            status_msg("Please enter a voice name.")
            return(invisible(NULL))
        }

        # Sanitize: alphanumeric, dash and underscore only. This is the
        # only guard between a typed name and a file path.
        voice_name <- gsub("[^a-zA-Z0-9_-]", "_", trimws(voice_name))

        dir <- voices_dir()
        if (!dir.exists(dir)) {
            dir.create(dir, recursive = TRUE, showWarnings = FALSE)
        }

        gen <- last_generation()
        ext <- if (!is.null(gen$format)) gen$format else "wav"
        dest_file <- file.path(dir, paste0(voice_name, ".", ext))

        tryCatch({
            writeBin(audio_data(), dest_file)
            glinty::remove_modal(session)
            status_msg(paste0("Saved voice: ", voice_name))

            voice_refresh(voice_refresh() + 1)
            if (current_backend() %in% c("chatterbox", "qwen3", "native")) {
                glinty::update_select_input(session, "voice",
                    choices = get_voices_for_backend(current_backend())$choices,
                    selected = paste0("custom:", voice_name))
            }
        }, error = function(e) {
            status_msg(paste("Error saving voice:", conditionMessage(e)))
        })
    })

    # History list rendering
    output$history_list <- glinty::render_ui(function() {
        hist <- history()
        sel <- selected_entry()

        if (length(hist) == 0) {
            return(glinty::txt("No generations yet", variant = "muted"))
        }

        items <- lapply(hist, function(entry) {
            is_selected <- !is.null(sel) && identical(sel, entry$id)

            params <- if (!is.null(entry$params) && length(entry$params) > 0) {
                glinty::txt(paste(names(entry$params), "=",
                                  unlist(entry$params), collapse = ", "),
                            variant = "muted")
            } else {
                NULL
            }

            # The timestamp is the button, and it carries the entry id
            # as its value -- one observer below serves every row and
            # reads which. Under protocol 2 this was a click bind on
            # the whole card, with the delete button nested inside it;
            # v3 has no clickable container, and nesting a button in
            # one was never valid markup anyway. Two buttons, side by
            # side, each saying what it does.
            glinty::panel(
                          variant = if (is_selected) "card" else "plain",
                          glinty::row(
                                      align = "center", gap = 8L,
                                      glinty::row(
                        grow = 1L,
                        glinty::button("history_click",
                                       format_timestamp(entry$timestamp),
                                       variant = "ghost", value = entry$id)
                    ),
                                      glinty::txt(backend_label(entry$backend),
                        variant = "muted"),
                                      glinty::button("history_delete", "x",
                        variant = "ghost",
                        icon = "trash",
                        value = entry$id)
                ),
                          glinty::txt(truncate_text(entry$text, 60), variant = "muted"),
                          params
            )
        })

        do.call(glinty::column, c(items, list(gap = 8L)))
    })

    glinty::observe_event(input$history_click, function() {
        id <- input$history_click()
        hist <- history()

        idx <- which(vapply(hist, function(e) identical(e$id, id), logical(1)))
        if (length(idx) == 0) {
            return(invisible(NULL))
        }

        entry <- hist[[idx[[1]]]]
        selected_entry(id)

        if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
            audio_data(readBin(entry$audio_file, "raw",
                               file.info(entry$audio_file)$size))
            audio_file(entry$audio_file)

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

        glinty::update_text_input(session, "text_input", value = entry$text)

        status_msg(sprintf("Loaded: %s", format_timestamp(entry$timestamp)))
    })

    glinty::observe_event(input$history_delete, function() {
        id <- input$history_delete()

        updated <- delete_history_entry(history(), id)
        history(updated)
        save_history(updated)

        if (!is.null(selected_entry()) && identical(selected_entry(), id)) {
            selected_entry(NULL)
            audio_data(NULL)
            audio_file(NULL)
        }

        status_msg("Entry deleted.")
    })

    glinty::observe_event(input$clear_history, function() {
        hist <- history()
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

    # Outputs ----------------------------------------------------------

    output$header_status <- glinty::render_text(function() {
        status_msg()
    })

    output$char_count <- glinty::render_text(function() {
        text <- input$text_input()
        if (is.null(text)) return("0 chars")
        sprintf("%d chars", nchar(text))
    })

    output$backend_status <- glinty::render_text(function() {
        backend_label(current_backend())
    })

    # Says so when there is nothing to play, and gets out of the way
    # once there is. The empty slot beneath it is not self-explanatory.
    output$audio_status <- glinty::render_text(function() {
        if (is.null(audio_data())) {
            "No audio generated yet. Enter text and click Generate."
        } else {
            ""
        }
    })

    # render_audio() rather than a hand-built <audio> element: the
    # value is a source, and which element plays it is the frontend's
    # problem. NULL leaves the slot empty.
    output$audio_player <- glinty::render_audio(function() {
        data <- audio_data()
        if (is.null(data)) {
            return(NULL)
        }

        file <- audio_file()
        ext <- if (!is.null(file)) {
            tools::file_ext(file)
        } else {
            opt_str(input$output_format()) %||% "wav"
        }
        mime <- if (identical(ext, "mp3")) "audio/mpeg" else "audio/wav"

        paste0("data:", mime, ";base64,", jsonlite::base64_enc(data))
    })

    output$generation_details <- glinty::render_text(function() {
        gen <- last_generation()
        if (is.null(gen)) return("No generation yet.")
        generation_details(gen)
    })

    output$generated_text <- glinty::render_text(function() {
        gen <- last_generation()
        if (is.null(gen)) return("")
        gen$text
    })

    glinty::download_handler(
                             session, "download_audio",
                             filename = function() {
        fmt <- glinty::isolate(opt_str(input$output_format()) %||% "wav")
        paste0("cornfab_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".", fmt)
    },
                             content = function(file) {
        data <- glinty::isolate(audio_data())
        if (!is.null(data)) {
            writeBin(data, file)
        }
    }
    )

    invisible(NULL)
}

# Null coalesce; also treats zero-length as absent
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) {
    y
} else {
    x
}

# Normalize an input to a non-empty string, or NULL
#
# glinty inputs are NULL until set, and inputs created inside
# render_ui() stay NULL until the user touches them, so every optional
# read goes through here rather than bare nzchar().
opt_str <- function(x) {
    if (is.null(x) || length(x) != 1L) {
        return(NULL)
    }
    if (is.na(x) || !nzchar(as.character(x))) {
        return(NULL)
    }
    as.character(x)
}

# Normalize an input to a finite number, or NULL
opt_num <- function(x) {
    if (is.null(x) || length(x) != 1L) {
        return(NULL)
    }
    x <- suppressWarnings(as.numeric(x))
    if (is.na(x) || !is.finite(x)) {
        return(NULL)
    }
    x
}

# Where uploaded and saved voices live
voices_dir <- function() {
    file.path(Sys.getenv("HOME"), ".cornfab", "voices")
}

# Render the Details tab for one generation
generation_details <- function(gen) {
    params_str <- ""
    backend <- gen$backend

    if (!is.null(gen$speed) && gen$speed != 1.0) {
        params_str <- paste0(params_str, "Speed: ", gen$speed, "\n")
    }

    if (backend %in% c("chatterbox", "native")) {
        if (!is.null(gen$exaggeration)) {
            params_str <- paste0(params_str, "Exaggeration: ",
                                 gen$exaggeration, "\n")
        }
        if (!is.null(gen$cfg_weight)) {
            params_str <- paste0(params_str, "CFG Weight: ", gen$cfg_weight, "\n")
        }
    } else if (identical(backend, "elevenlabs")) {
        if (!is.null(gen$stability)) {
            params_str <- paste0(params_str, "Stability: ", gen$stability, "\n")
        }
        if (!is.null(gen$similarity)) {
            params_str <- paste0(params_str, "Similarity: ", gen$similarity, "\n")
        }
    } else if (identical(backend, "qwen3")) {
        if (!is.null(gen$language) && !identical(gen$language, "English")) {
            params_str <- paste0(params_str, "Language: ", gen$language, "\n")
        }
        if (!is.null(gen$instruct) && nzchar(gen$instruct)) {
            params_str <- paste0(params_str, "Instructions: ", gen$instruct, "\n")
        }
        if (!is.null(gen$voice_description) && nzchar(gen$voice_description)) {
            params_str <- paste0(params_str, "Voice Design: ",
                                 gen$voice_description, "\n")
        }
    }

    if (!is.null(gen$seed)) {
        params_str <- paste0(params_str, "Seed: ", gen$seed, "\n")
    }

    paste0(
           "Backend: ", backend_label(gen$backend), "\n",
           "Voice: ", gen$voice, "\n",
        if (!is.null(gen$model) && nzchar(gen$model)) {
            paste0("Model: ", gen$model, "\n")
        } else {
            ""
        },
           "Format: ", gen$format,
        if (nzchar(params_str)) paste0("\n\n", params_str) else ""
    )
}

# Get display label for backend
backend_label <- function(backend) {
    labels <- c(chatterbox = "Chatterbox (container)",
                native = "Chatterbox (native)",
                qwen3 = "Qwen3-TTS (container)", openai = "OpenAI TTS",
                elevenlabs = "ElevenLabs")
    if (backend %in% names(labels)) {
        labels[[backend]]
    } else {
        backend
    }
}

# Detect available backends
detect_backends <- function() {
    backends <- c()

    if (requireNamespace("chatterbox", quietly = TRUE)) {
        backends <- c(backends, "Chatterbox (native)" = "native")
    }

    backends <- c(backends, "Chatterbox (container)" = "chatterbox")

    # Offered either way; the URL is configurable in API Settings.
    backends <- c(backends, "Qwen3-TTS (container)" = "qwen3")

    if (nzchar(Sys.getenv("OPENAI_API_KEY", ""))) {
        backends <- c(backends, "OpenAI TTS" = "openai")
    }

    if (nzchar(Sys.getenv("ELEVENLABS_API_KEY", ""))) {
        backends <- c(backends, "ElevenLabs" = "elevenlabs")
    }

    backends
}

# Configure backend
configure_backend <- function(backend) {
    if (identical(backend, "openai")) {
        tts.api::set_tts_base("https://api.openai.com")
        key <- Sys.getenv("OPENAI_API_KEY", "")
        if (nzchar(key)) {
            tts.api::set_tts_key(key)
        }
    } else if (identical(backend, "chatterbox")) {
        tts.api::set_tts_base(.cornfab_service_url("chatterbox",
                Sys.getenv("TTS_API_BASE", "http://localhost:7810")))
    } else if (identical(backend, "native")) {
        # Native chatterbox - model loads in the R process, nothing to set
    } else if (identical(backend, "qwen3")) {
        tts.api::set_tts_base(.cornfab_service_url("qwen3-tts",
                Sys.getenv("QWEN3_TTS_BASE", "http://localhost:7811")))
    } else if (identical(backend, "elevenlabs")) {
        key <- Sys.getenv("ELEVENLABS_API_KEY", "")
        if (nzchar(key)) {
            tts.api::set_elevenlabs_key(key)
        }
    }
}

# Get models for backend
get_models_for_backend <- function(backend) {
    if (identical(backend, "openai")) {
        list(choices = c("tts-1" = "tts-1", "tts-1-hd" = "tts-1-hd"),
             default = "tts-1")
    } else if (identical(backend, "elevenlabs")) {
        list(
             choices = c(
                         "Multilingual v2" = "eleven_multilingual_v2",
                         "Turbo v2.5" = "eleven_turbo_v2_5",
                         "English v1" = "eleven_monolingual_v1"
            ),
             default = "eleven_multilingual_v2"
        )
    } else if (identical(backend, "qwen3")) {
        list(
             choices = c(
                         "Qwen3-TTS 1.7B" = "Qwen/Qwen3-TTS",
                         "Qwen3-TTS 0.6B" = "Qwen/Qwen3-TTS-0.6B"
            ),
             default = "Qwen/Qwen3-TTS"
        )
    } else {
        # Chatterbox (native and container) needs no model selection
        list(choices = character(0), default = NULL)
    }
}

# Get local custom voices
get_local_voices <- function() {
    dir <- voices_dir()
    if (!dir.exists(dir)) {
        return(character(0))
    }

    files <- list.files(dir, pattern = "\\.(wav|mp3|m4a|ogg|flac)$",
                        ignore.case = TRUE)
    if (length(files) == 0) {
        return(character(0))
    }

    voice_names <- tools::file_path_sans_ext(files)
    stats::setNames(paste0("custom:", voice_names),
                    paste0(voice_names, " (custom)"))
}

# Get service URL from gpu.ctl or use fallback
.cornfab_service_url <- function(svc_name, fallback) {
    if (requireNamespace("gpu.ctl", quietly = TRUE)) {
        url <- tryCatch(gpu.ctl::gpu_service_url(svc_name),
                        error = function(e) NULL)
        if (!is.null(url)) {
            return(url)
        }
    }
    fallback
}

# Map container name to gpu.ctl service name
.cornfab_svc_name <- function(container) {
    map <- c("qwen3-tts-api" = "qwen3-tts", "chatterbox" = "chatterbox")
    unname(map[container]) %||% container
}

# Acquire GPU service (gpu.ctl with docker fallback)
.cornfab_gpu_acquire <- function(container, status_msg) {
    svc_name <- .cornfab_svc_name(container)

    if (requireNamespace("gpu.ctl", quietly = TRUE) &&
        svc_name %in% gpu.ctl::gpu_services()$name) {
        tryCatch({
            gpu.ctl::gpu_acquire(svc_name)
            url <- gpu.ctl::gpu_service_url(svc_name)
            if (!is.null(url)) tts.api::set_tts_base(url)
            status_msg(paste0("Service ready: ", svc_name))
        }, error = function(e) {
            status_msg(paste("Start failed:", conditionMessage(e)))
        })
    } else {
        result <- tryCatch(
                           system2("docker", c("start", container), stdout = TRUE,
                                   stderr = TRUE),
                           error = function(e) conditionMessage(e)
        )
        if (any(grepl(container, result))) {
            status_msg("Container started. Waiting for model to load...")
        } else {
            status_msg(paste("Start failed:", paste(result, collapse = " ")))
        }
    }
}

# Release GPU service (gpu.ctl with docker fallback)
.cornfab_gpu_release <- function(container, status_msg) {
    svc_name <- .cornfab_svc_name(container)

    if (requireNamespace("gpu.ctl", quietly = TRUE) &&
        svc_name %in% gpu.ctl::gpu_services()$name) {
        tryCatch({
            gpu.ctl::gpu_release(svc_name)
            status_msg(paste0("Service stopped: ", svc_name))
        }, error = function(e) {
            status_msg(paste("Stop failed:", conditionMessage(e)))
        })
    } else {
        system2("docker", c("stop", container), stdout = TRUE, stderr = TRUE)
        status_msg("Container stopped.")
    }
}

# Get voices for backend
get_voices_for_backend <- function(backend) {
    if (identical(backend, "openai")) {
        list(
             choices = c("Alloy" = "alloy", "Ash" = "ash",
                         "Ballad" = "ballad", "Coral" = "coral",
                         "Echo" = "echo", "Fable" = "fable", "Nova" = "nova",
                         "Onyx" = "onyx", "Sage" = "sage",
                         "Shimmer" = "shimmer", "Verse" = "verse"),
             default = "nova"
        )
    } else if (identical(backend, "elevenlabs")) {
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
    } else if (identical(backend, "qwen3")) {
        builtin <- c(
                     "Vivian" = "Vivian", "Serena" = "Serena", "Uncle Fu" = "Uncle_Fu",
                     "Dylan" = "Dylan", "Eric" = "Eric", "Ryan" = "Ryan",
                     "Aiden" = "Aiden", "Ono Anna" = "Ono_Anna", "Sohee" = "Sohee"
        )
        list(choices = c(builtin, get_local_voices()), default = "Vivian")
    } else if (identical(backend, "chatterbox")) {
        custom <- get_local_voices()
        list(
             choices = c(custom, "Default" = "default"),
             default = if (length(custom) > 0) unname(custom[1]) else "default"
        )
    } else if (identical(backend, "native")) {
        jfk_path <- system.file("audio", "jfk.wav", package = "cornfab")
        list(
             choices = c(c("JFK Sample" = jfk_path), get_local_voices()),
             default = jfk_path
        )
    } else {
        list(choices = c("Default" = "default"), default = "default")
    }
}
