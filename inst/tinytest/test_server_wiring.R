# Server-side wiring against a headless glinty session. No browser:
# build the session, feed it the messages a client would, and read
# what the server queued back.

new_session <- glinty:::new_session
session_end <- glinty:::session_end
with_session <- glinty:::with_session
tag_to_html <- glinty:::tag_to_html
handle_download <- glinty:::handle_download
handle_input <- glinty:::handle_input

app_ui <- cornfab:::app_ui
app_server <- cornfab:::app_server
opt_str <- cornfab:::opt_str
opt_num <- cornfab:::opt_num
icon <- cornfab:::icon
icon_button <- cornfab:::icon_button
backend_label <- cornfab:::backend_label
detect_backends <- cornfab:::detect_backends
get_models_for_backend <- cornfab:::get_models_for_backend
get_voices_for_backend <- cornfab:::get_voices_for_backend
generation_details <- cornfab:::generation_details

# --- the UI tree builds and renders ---
html <- tag_to_html(app_ui())
expect_true(nchar(html) > 5000)
expect_true(grepl("g-tabset", html, fixed = TRUE))
expect_true(grepl("data-g-cond", html, fixed = TRUE))
expect_true(grepl("data-g-download", html, fixed = TRUE))

# --- neither API key reaches the page ---
# type="password" only masks on screen; a value= attribute is plain
# text in the source, and glinty serves on all interfaces.
expect_true(grepl('id="openai_key"', html, fixed = TRUE))
expect_true(grepl('id="elevenlabs_key"', html, fixed = TRUE))
expect_false(grepl("sk-", html, fixed = TRUE))
for (var in c("OPENAI_API_KEY", "ELEVENLABS_API_KEY")) {
  key <- Sys.getenv(var, "")
  if (nzchar(key)) {
    expect_false(grepl(key, html, fixed = TRUE))
  }
}

# --- icons are real SVG trees, not markup strings ---
ic <- icon("play")
expect_equal(ic$tag, "svg")
expect_equal(ic$attrs$viewBox, "0 0 24 24")
expect_true(length(ic$children) >= 1L)
expect_equal(ic$children[[1]]$tag, "polygon")
# every icon the app uses resolves
for (nm in c("play", "stop", "rotate", "trash", "microphone", "bookmark",
             "download")) {
  expect_equal(icon(nm)$tag, "svg")
}
expect_error(icon("nonexistent"), "unknown icon")

# an icon button binds its click and carries the svg as a child
ib <- icon_button("clear_history", "trash", "Clear all history")
expect_equal(ib$bind$target, "clear_history")
expect_equal(ib$children[[1]]$tag, "svg")
# and survives the wire format, which is where the SVG namespace bug
# bit: these trees are rebuilt client-side by buildTagNode()
wire <- glinty:::unclass_recursive(ib)
expect_equal(wire$children[[1]]$tag, "svg")
shape_tags <- vapply(wire$children[[1]]$children,
                     function(x) x$tag, character(1L))
expect_true(all(shape_tags %in% c("path", "line", "rect", "polygon",
                                  "polyline")))
expect_true(length(shape_tags) > 0L)

# --- input guards ---
expect_null(opt_str(NULL))
expect_null(opt_str(""))
expect_null(opt_str(NA))
expect_null(opt_str(character(0)))
expect_equal(opt_str("qwen3"), "qwen3")

expect_null(opt_num(NULL))
expect_null(opt_num(NA))
expect_null(opt_num("not a number"))
expect_null(opt_num(character(0)))
expect_equal(opt_num(0.5), 0.5)
expect_equal(opt_num("1.5"), 1.5)
# a seed left blank is absent, not zero
expect_null(opt_num(NA_integer_))

# --- backend metadata ---
expect_equal(backend_label("qwen3"), "Qwen3-TTS (container)")
expect_equal(backend_label("mystery"), "mystery")

backends <- detect_backends()
expect_true("chatterbox" %in% backends)
expect_true("qwen3" %in% backends)

# chatterbox needs no model; the UI hides the section on an empty list
expect_equal(length(get_models_for_backend("chatterbox")$choices), 0L)
expect_equal(get_models_for_backend("openai")$default, "tts-1")
expect_equal(get_voices_for_backend("openai")$default, "nova")
expect_true("Vivian" %in% get_voices_for_backend("qwen3")$choices)

# --- generation_details renders per backend ---
gen <- list(backend = "chatterbox", voice = "default", model = NULL,
            format = "wav", speed = 1.5, exaggeration = 0.7,
            cfg_weight = 0.4)
details <- generation_details(gen)
expect_true(grepl("Chatterbox (container)", details, fixed = TRUE))
expect_true(grepl("Speed: 1.5", details, fixed = TRUE))
expect_true(grepl("Exaggeration: 0.7", details, fixed = TRUE))
# elevenlabs params do not leak into a chatterbox report
expect_false(grepl("Stability", details, fixed = TRUE))
# a default speed is omitted rather than printed
expect_false(grepl("Speed",
                   generation_details(list(backend = "openai",
                                           voice = "nova", format = "mp3",
                                           speed = 1.0)),
                   fixed = TRUE))

# --- the server starts and seeds its outputs ---
s <- new_session("c1")
with_session(s, app_server(s$input, s$output, s))
glinty::flush_reactions()
expect_true(length(s$outgoing) > 0L)
sent <- lapply(s$outgoing, function(m) jsonlite::fromJSON(m,
                                                          simplifyVector = FALSE))
ids <- vapply(Filter(function(m) identical(m$type, "update"), sent),
              function(m) m$id, character(1L))
expect_true("header_status" %in% ids)
expect_true("char_count" %in% ids)

# char_count reacts to the textarea
handle_input(s, "text_input", "hello")
glinty::flush_reactions()
sent <- lapply(s$outgoing, function(m) jsonlite::fromJSON(m,
                                                          simplifyVector = FALSE))
counts <- Filter(function(m) identical(m$id, "char_count"), sent)
expect_true(length(counts) > 0L)
expect_equal(counts[[length(counts)]]$value, "5 chars")

# --- the download is registered, and names files sensibly ---
expect_true("download_audio" %in% ls(s$downloads))
handler <- s$downloads[["download_audio"]]
expect_true(is.function(handler$filename))
expect_true(is.function(handler$content))

name <- handler$filename()
expect_true(grepl("^cornfab_[0-9]{8}_[0-9]{6}\\.wav$", name))
# the extension follows the format select
handle_input(s, "output_format", "mp3")
expect_true(grepl("\\.mp3$", handler$filename()))
handle_input(s, "output_format", "wav")

# With no audio generated, content writes nothing and glinty answers
# 500 rather than serving an empty file. An honest error beats a
# 0-byte download the browser would happily save.
req <- list(method = "GET", path = "/download",
            query = "session=c1&id=download_audio")
resp <- rawToChar(handle_download(req))
expect_true(grepl("500", resp, fixed = TRUE))

session_end(s)
