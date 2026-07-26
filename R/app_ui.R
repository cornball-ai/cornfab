#' App UI
#'
#' Create the Cornfab app user interface.
#'
#' Assets are served from inst/app/www under /static/ by run_app().
#'
#' @return A glinty UI tree.
#'
#' @keywords internal
app_ui <- function() {
    # Placeholder for an API key field.
    #
    # Reports whether an environment key is in play without putting the
    # key itself anywhere near the page. A value= attribute is rendered
    # into the page source in plain text, where type="password" hides
    # nothing, and glinty serves on all interfaces.
    key_placeholder <- function(var) {
        if (nzchar(Sys.getenv(var, ""))) {
            paste0("using ", var, " (type to override)")
        } else {
            "paste key to set"
        }
    }

    glinty::page(
                 title = "cornfab",
                 css = "/static/styles.css",
                 favicon = "/static/logo.png",

                 # Header
                 glinty::div(
                             class = "cornfab-header",
                             glinty::div(
                class = "header-content",
                glinty::tag(
                            "a",
                            attrs = list(href = "https://cornball.ai",
                        target = "_blank", class = "header-link"),
                            children = list(
                        glinty::tag("img", attrs = list(src = "/static/logo.png",
                                class = "header-logo", alt = "cornball.ai")),
                        glinty::span("cornfab", class = "header-title")
                    )
                ),
                glinty::div(class = "header-spacer"),
                glinty::div(
                            class = "header-status",
                            glinty::text_output("header_status")
                )
            )
        ),

                 glinty::div(
                             class = "main-container",

                             # Left sidebar - History
                             glinty::div(
                class = "left-sidebar",
                glinty::div(
                            class = "sidebar-header",
                            glinty::span("History"),
                            icon_button("clear_history", "trash", "Clear all history",
                                        class = "btn-sm")
                ),
                glinty::div(
                            class = "sidebar-options",
                            glinty::checkbox_input("save_audio", "Save audio files", TRUE)
                ),
                glinty::div(
                            class = "history-list",
                            glinty::ui_output("history_list")
                )
            ),

                             # Center content
                             glinty::div(
                class = "center-content",

                # Input panel
                glinty::div(
                            class = "input-panel",
                            glinty::div(
                                        class = "panel-header",
                                        glinty::span("Text Input"),
                                        glinty::span(class = "char-count",
                            glinty::text_output("char_count"))
                    ),
                            glinty::div(
                                        class = "text-input-wrapper",
                                        glinty::textarea_input(
                            "text_input", "",
                            rows = 8L,
                            placeholder = "Enter text to convert to speech..."
                        )
                    ),
                            glinty::div(
                                        class = "input-controls",
                                        icon_label_button("generate", "play", "Generate Speech",
                            class = "btn-generate")
                    )
                ),

                # Output panel
                glinty::div(
                            class = "output-panel",
                            glinty::div(
                                        class = "panel-header",
                                        glinty::span("Generated Audio")
                    ),
                            glinty::div(
                                        class = "audio-container",
                                        glinty::ui_output("audio_player")
                    ),
                            glinty::div(
                                        class = "output-controls",
                                        glinty::download_button("download_audio", "Download",
                            class = "btn-download"),
                                        icon_label_button("save_as_voice", "microphone", "Save as Voice",
                            class = "btn-secondary"),
                                        icon_label_button("copy_to_history", "bookmark", "Save to History",
                            class = "btn-secondary")
                    ),
                            glinty::tabset(
                        glinty::tab_panel(
                            "Details",
                            glinty::div(
                                        class = "details-content",
                                        glinty::verbatim_output("generation_details")
                            )
                        ),
                        glinty::tab_panel(
                            "Text",
                            glinty::div(
                                        class = "text-content",
                                        glinty::verbatim_output("generated_text")
                            )
                        ),
                        id = "output_tabs"
                    )
                )
            ),

                             # Right sidebar - Settings
                             glinty::div(
                class = "right-sidebar",

                # Backend section
                glinty::div(
                            class = "settings-section",
                            glinty::div(class = "section-title", "Backend"),
                            glinty::select_input(
                        "backend", "",
                        choices = c("Chatterbox" = "chatterbox"),
                        selected = "chatterbox"
                    ),
                            glinty::ui_output("backend_status")
                ),

                # Voice section
                glinty::div(
                            class = "settings-section",
                            glinty::div(
                                        class = "section-title-row",
                                        glinty::span("Voice", class = "section-title"),
                                        icon_button("refresh_voices", "rotate", "Refresh voice list",
                            class = "btn-sm")
                    ),
                            # Voice Design toggle (qwen3 only)
                            glinty::conditional_panel(
                        condition = glinty::input_is("backend", "qwen3"),
                        glinty::div(
                                    class = "voice-design-toggle",
                                    glinty::checkbox_input("use_voice_design",
                                "Design voice from description", FALSE)
                        )
                    ),
                            # Voice selector (hidden when voice design is active)
                            glinty::conditional_panel(
                        condition = glinty::cond_not(glinty::cond_and(
                                glinty::input_is("backend", "qwen3"),
                                glinty::input_is("use_voice_design", TRUE)
                            )),
                        glinty::ui_output("voice_select")
                    ),
                            # Voice description (qwen3 voice design mode)
                            glinty::conditional_panel(
                        condition = glinty::cond_and(
                            glinty::input_is("backend", "qwen3"),
                            glinty::input_is("use_voice_design", TRUE)
                        ),
                        glinty::div(
                                    class = "voice-design-section",
                                    glinty::textarea_input(
                                "voice_description", "",
                                rows = 3L,
                                placeholder = paste("Describe the voice you want, e.g.,",
                                    "'A warm, friendly female voice with a slight",
                                    "British accent'")
                            )
                        )
                    ),
                            # Voice upload - hidden in design mode
                            glinty::conditional_panel(
                        condition = glinty::cond_and(
                            glinty::input_is("backend", c("chatterbox", "qwen3", "native")),
                            glinty::cond_not(glinty::cond_and(
                                    glinty::input_is("backend", "qwen3"),
                                    glinty::input_is("use_voice_design", TRUE)
                                ))
                        ),
                        glinty::div(
                                    class = "voice-upload-section",
                                    glinty::file_input(
                                "voice_upload", "Add Voice",
                                accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac")
                            ),
                                    glinty::ui_output("upload_status")
                        )
                    )
                ),

                # Model section (conditional on backend)
                glinty::ui_output("model_section"),

                # Parameters section
                glinty::div(
                            class = "settings-section",
                            glinty::tag(
                                        "details",
                                        attrs = list(class = "params-details", open = "open"),
                                        children = list(
                            glinty::tag("summary", text = "Parameters"),
                            glinty::div(
                                        class = "params-content",
                                        glinty::slider_input("speed", "Speed",
                                    min = 0.5, max = 2.0, value = 1.0, step = 0.1),
                                        # Chatterbox-specific
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend",
                                        c("chatterbox", "native")),
                                    glinty::slider_input("exaggeration", "Exaggeration",
                                        min = 0.25, max = 1, value = 0.5, step = 0.05),
                                    glinty::slider_input("cfg_weight", "CFG Weight",
                                        min = 0, max = 1, value = 0.5, step = 0.05)
                                ),
                                        # ElevenLabs-specific
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "elevenlabs"),
                                    glinty::slider_input("stability", "Stability",
                                        min = 0, max = 1, value = 0.5, step = 0.05),
                                    glinty::slider_input("similarity", "Similarity Boost",
                                        min = 0, max = 1, value = 0.75, step = 0.05)
                                ),
                                        # Qwen3-specific
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "qwen3"),
                                    glinty::select_input(
                                        "language", "Language",
                                        choices = c(
                                            "English" = "English",
                                            "Spanish" = "Spanish",
                                            "Chinese" = "Chinese",
                                            "Japanese" = "Japanese",
                                            "Korean" = "Korean",
                                            "French" = "French",
                                            "German" = "German",
                                            "Italian" = "Italian",
                                            "Portuguese" = "Portuguese",
                                            "Russian" = "Russian"
                                        ),
                                        selected = "English"
                                    ),
                                    glinty::text_input("instruct", "Voice Instructions",
                                        placeholder = "e.g., Speak cheerfully")
                                ),
                                        glinty::number_input("seed", "Seed (optional)")
                            )
                        )
                    )
                ),

                # API Settings section
                glinty::div(
                            class = "settings-section",
                            glinty::tag(
                                        "details",
                                        attrs = list(class = "api-details"),
                                        children = list(
                            glinty::tag("summary", text = "API Settings"),
                            glinty::div(
                                        class = "api-content",
                                        # Chatterbox URL and container control
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "chatterbox"),
                                    glinty::text_input("chatterbox_url", "Chatterbox URL",
                                        value = Sys.getenv("TTS_API_BASE",
                                            "http://localhost:7810")),
                                    glinty::div(
                                        class = "container-control",
                                        glinty::ui_output("chatterbox_container_btn")
                                    )
                                ),
                                        # Qwen3-TTS URL and container control
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "qwen3"),
                                    glinty::text_input("qwen3_url", "Qwen3-TTS URL",
                                        value = Sys.getenv("QWEN3_TTS_BASE",
                                            "http://localhost:7811")),
                                    glinty::div(
                                        class = "container-control",
                                        glinty::ui_output("qwen3_container_btn")
                                    )
                                ),
                                        # API keys are never prefilled; see key_placeholder()
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "openai"),
                                    glinty::password_input("openai_key", "OpenAI API Key",
                                        placeholder = key_placeholder("OPENAI_API_KEY"))
                                ),
                                        glinty::conditional_panel(
                                    condition = glinty::input_is("backend", "elevenlabs"),
                                    glinty::password_input("elevenlabs_key",
                                        "ElevenLabs API Key",
                                        placeholder = key_placeholder("ELEVENLABS_API_KEY"))
                                )
                            )
                        )
                    )
                ),

                # Output format
                glinty::div(
                            class = "settings-section",
                            glinty::div(class = "section-title", "Output Format"),
                            glinty::select_input(
                        "output_format", "",
                        choices = c("WAV" = "wav", "MP3" = "mp3"),
                        selected = "wav"
                    )
                )
            )
        )
    )
}
