#' App UI
#'
#' Create the Cornfab app user interface.
#'
#' Assets are served from inst/app/www under /static/ by run_app().
#'
#' Built from glinty's component vocabulary rather than from HTML
#' tags: the tree travels the wire as components, so a non-browser
#' frontend renders the same app with real widgets. Anything reached
#' for here that the vocabulary does not supply is a finding against
#' glinty, not something to paper over with raw markup.
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

                 # Header. The grown row is the spacer: it takes the
                 # leftover width, which pushes the status to the far
                 # edge without a div whose only job is to be empty.
                 glinty::panel(
                               id = "cornfab-header",
                               glinty::row(
                    align = "center", gap = 12L,
                    glinty::row(
                                grow = 1L,
                                glinty::link(
                            href = "https://cornball.ai", external = TRUE,
                            children = list(glinty::row(
                                    align = "center", gap = 10L,
                                    glinty::image("/static/logo.png",
                                                  alt = "cornball.ai", height = 32L),
                                    glinty::txt("cornfab", variant = "heading")
                                ))
                        )
                    ),
                    glinty::text_output("header_status", variant = "muted")
                )
        ),

                 glinty::row(
                             id = "main-layout", gap = 16L,

                             # Left sidebar - History
                             glinty::panel(
                variant = "sidebar", width = 280L, id = "left-sidebar",
                glinty::row(
                            align = "center", gap = 8L,
                            glinty::row(grow = 1L, glinty::txt("History",
                                    variant = "strong")),
                            # A label as well as the icon: an icon-only
                            # button has no accessible name, and the
                            # component vocabulary has nowhere to put
                            # one.
                            glinty::button("clear_history", "Clear",
                                           icon = "trash", variant = "ghost")
                ),
                glinty::checkbox_input("save_audio", "Save audio files", TRUE),
                glinty::ui_output("history_list")
            ),

                             # Center content
                             glinty::column(
                grow = 1L, gap = 16L, id = "center-content",

                # Input panel
                glinty::panel(
                              variant = "card", id = "input-panel",
                              glinty::row(
                        align = "center", gap = 8L,
                        glinty::row(grow = 1L, glinty::txt("Text Input",
                                variant = "strong")),
                        glinty::text_output("char_count", variant = "muted")
                    ),
                              glinty::textarea_input(
                        "text_input", "",
                        rows = 8L,
                        placeholder = "Enter text to convert to speech..."
                    ),
                              glinty::button("generate", "Generate Speech",
                                             icon = "play", variant = "primary")
                ),

                # Output panel
                glinty::panel(
                              variant = "card", id = "output-panel",
                              glinty::txt("Generated Audio", variant = "strong"),
                              # Empty once there is audio; the slot
                              # below plays it. A message is text, and
                              # text_output is where text goes.
                              glinty::text_output("audio_status",
                                                  variant = "muted"),
                              glinty::audio_output("audio_player",
                                                   autoplay = TRUE),
                              glinty::row(
                        gap = 8L,
                        glinty::download_button("download_audio", "Download",
                                                icon = "download"),
                        glinty::button("save_as_voice", "Save as Voice",
                                       icon = "microphone",
                                       variant = "secondary"),
                        glinty::button("copy_to_history", "Save to History",
                                       icon = "bookmark",
                                       variant = "secondary")
                    ),
                              glinty::tabset(
                        glinty::tab_panel(
                            "Details",
                            glinty::verbatim_output("generation_details")
                        ),
                        glinty::tab_panel(
                            "Text",
                            glinty::verbatim_output("generated_text")
                        ),
                        id = "output_tabs"
                    )
                )
            ),

                             # Right sidebar - Settings
                             glinty::column(
                width = 280L, gap = 16L, id = "right-sidebar",

                # Backend section
                glinty::panel(
                              variant = "sidebar", title = "Backend",
                              glinty::select_input(
                        "backend", "",
                        choices = c("Chatterbox" = "chatterbox"),
                        selected = "chatterbox"
                    ),
                              glinty::text_output("backend_status",
                                                  variant = "muted")
                ),

                # Voice section
                glinty::panel(
                              variant = "sidebar",
                              glinty::row(
                        align = "center", gap = 8L,
                        glinty::row(grow = 1L, glinty::txt("Voice",
                                variant = "strong")),
                        glinty::button("refresh_voices", "Refresh",
                                       icon = "rotate", variant = "ghost")
                    ),
                              # Voice Design toggle (qwen3 only)
                              glinty::conditional_panel(
                        condition = glinty::input_is("backend", "qwen3"),
                        glinty::checkbox_input("use_voice_design",
                                               "Design voice from description",
                                               FALSE)
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
                        glinty::textarea_input(
                            "voice_description", "",
                            rows = 3L,
                            placeholder = paste("Describe the voice you want, e.g.,",
                                "'A warm, friendly female voice with a slight",
                                "British accent'")
                        )
                    ),
                              # Voice upload - hidden in design mode
                              glinty::conditional_panel(
                        condition = glinty::cond_and(
                            glinty::input_is("backend",
                                             c("chatterbox", "qwen3", "native")),
                            glinty::cond_not(glinty::cond_and(
                                    glinty::input_is("backend", "qwen3"),
                                    glinty::input_is("use_voice_design", TRUE)
                                ))
                        ),
                        glinty::file_input(
                            "voice_upload", "Add Voice",
                            accept = c(".wav", ".mp3", ".m4a", ".ogg", ".flac")
                        ),
                        glinty::ui_output("upload_status")
                    )
                ),

                # Model section (conditional on backend)
                glinty::ui_output("model_section"),

                # Parameters section
                glinty::panel(
                              variant = "sidebar",
                              glinty::collapse(
                        title = "Parameters", open = TRUE, id = "params",
                        glinty::slider_input("speed", "Speed",
                                             min = 0.5, max = 2.0, value = 1.0,
                                             step = 0.1),
                        # Chatterbox-specific
                        glinty::conditional_panel(
                            condition = glinty::input_is("backend",
                                                         c("chatterbox", "native")),
                            glinty::slider_input("exaggeration", "Exaggeration",
                                                 min = 0.25, max = 1, value = 0.5,
                                                 step = 0.05),
                            glinty::slider_input("cfg_weight", "CFG Weight",
                                                 min = 0, max = 1, value = 0.5,
                                                 step = 0.05)
                        ),
                        # ElevenLabs-specific
                        glinty::conditional_panel(
                            condition = glinty::input_is("backend", "elevenlabs"),
                            glinty::slider_input("stability", "Stability",
                                                 min = 0, max = 1, value = 0.5,
                                                 step = 0.05),
                            glinty::slider_input("similarity", "Similarity Boost",
                                                 min = 0, max = 1, value = 0.75,
                                                 step = 0.05)
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
                ),

                # API Settings section
                glinty::panel(
                              variant = "sidebar",
                              glinty::collapse(
                        title = "API Settings", id = "api-settings",
                        # Chatterbox URL and container control
                        glinty::conditional_panel(
                            condition = glinty::input_is("backend", "chatterbox"),
                            glinty::text_input("chatterbox_url", "Chatterbox URL",
                                               value = Sys.getenv("TTS_API_BASE",
                                                   "http://localhost:7810")),
                            glinty::ui_output("chatterbox_container_btn")
                        ),
                        # Qwen3-TTS URL and container control
                        glinty::conditional_panel(
                            condition = glinty::input_is("backend", "qwen3"),
                            glinty::text_input("qwen3_url", "Qwen3-TTS URL",
                                               value = Sys.getenv("QWEN3_TTS_BASE",
                                                   "http://localhost:7811")),
                            glinty::ui_output("qwen3_container_btn")
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
                ),

                # Output format
                glinty::panel(
                              variant = "sidebar", title = "Output Format",
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
