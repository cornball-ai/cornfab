# Server-side wiring against a headless glinty session. No browser:
# build the session, feed it the messages a client would, and read
# what the server queued back.

new_session <- glinty:::new_session
session_end <- glinty:::session_end
with_session <- glinty:::with_session
component_to_html <- glinty:::component_to_html
handle_download <- glinty:::handle_download
handle_input <- glinty:::handle_input

app_ui <- cornfab:::app_ui
app_server <- cornfab:::app_server
opt_str <- cornfab:::opt_str
opt_num <- cornfab:::opt_num
backend_label <- cornfab:::backend_label
detect_backends <- cornfab:::detect_backends
get_models_for_backend <- cornfab:::get_models_for_backend
get_voices_for_backend <- cornfab:::get_voices_for_backend
generation_details <- cornfab:::generation_details

json <- function(x) jsonlite::fromJSON(x, simplifyVector = FALSE)

sent_of <- function(s, type) {
  Filter(function(m) identical(m$type, type), lapply(s$outgoing, json))
}

# --- the UI tree builds and renders ---
ui <- app_ui()
html <- component_to_html(ui)
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

# --- every icon the app asks for is one glinty draws ---
#
# The icon name is an enum in the component schema, so a typo fails
# where it is written rather than rendering an invisible span. cornfab
# used to carry its own SVG paths for these; glinty draws them now,
# and this is what keeps the app's set inside the vocabulary's.
icons <- unique(gsub('.*g-icon-([a-z]+).*', "\\1",
                     regmatches(html, gregexpr("g-icon-[a-z]+", html))[[1]]))
expect_true(length(icons) > 0L)
expect_equal(setdiff(icons, glinty:::ICON_NAMES), character(0))
# and one that is not in the set is refused at the call
expect_error(glinty::icon("nonexistent"))

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
ids <- vapply(sent_of(s, "output"), function(m) m$id, character(1L))
expect_true("header_status" %in% ids)
expect_true("char_count" %in% ids)

# char_count reacts to the textarea
handle_input(s, "text_input", "hello")
glinty::flush_reactions()
counts <- Filter(function(m) identical(m$id, "char_count"), sent_of(s, "output"))
expect_true(length(counts) > 0L)
expect_equal(counts[[length(counts)]]$value, "5 chars")

# the audio slot says why it is empty, and stops once it is not
statuses <- Filter(function(m) identical(m$id, "audio_status"),
                   sent_of(s, "output"))
expect_true(length(statuses) > 0L)
expect_true(grepl("No audio generated yet", statuses[[1]]$value, fixed = TRUE))

# --- history rows carry their own id on a valued button ---
#
# Protocol 2 put a click bind on the row div and nested the delete
# button inside it. v3 has no clickable container, and a button inside
# a button was never valid markup: two buttons side by side, each
# carrying the entry id as its value, with one observer per handler
# reading which.
s2 <- new_session("c2")
entry <- list(id = "gen_42", text = "hello world", timestamp = Sys.time(),
              backend = "chatterbox")
with_session(s2, {
  s2$output$history_list <- glinty::render_ui(function() {
    glinty::row(
      glinty::button("history_click", "12:04", variant = "ghost",
                     value = entry$id),
      glinty::button("history_delete", "x", variant = "ghost",
                     icon = "trash", value = entry$id))
  })
})
glinty::flush_reactions()
ui_msgs <- Filter(function(m) identical(m$kind, "ui"), sent_of(s2, "output"))
expect_true(length(ui_msgs) > 0L)
row <- ui_msgs[[length(ui_msgs)]]$value
expect_equal(row$children[[1]]$id, "history_click")
expect_equal(row$children[[1]]$value, "gen_42")
expect_equal(row$children[[2]]$id, "history_delete")
expect_equal(row$children[[2]]$value, "gen_42")

# and a list of them lowers without a duplicate DOM id: the component
# id names the handler, not the element, which is what lets rows share
# one
rows_html <- component_to_html(glinty::column(
  glinty::button("history_click", "a", value = "a"),
  glinty::button("history_click", "b", value = "b")))
expect_false(grepl(' id="history_click"', rows_html, fixed = TRUE))
expect_equal(length(gregexpr('data-g-value="', rows_html)[[1]]), 2L)
session_end(s2)

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

# A download is redeemed against a ticket, not a session id in the
# query: v3 moved the credential off the URL, so an unticketed request
# is refused before it reaches the handler at all.
req <- list(method = "GET", path = "/download",
            query = "session=c1&id=download_audio")
expect_true(grepl("403", rawToChar(handle_download(req)), fixed = TRUE))

# With a real ticket and no audio generated, content writes nothing
# and glinty answers 500 rather than serving an empty file. An honest
# error beats a 0-byte download the browser would happily save.
grant <- glinty:::issue_ticket(s, "download_audio", "download")
resp <- rawToChar(handle_download(list(method = "GET", path = "/download",
                                       query = paste0("ticket=", grant$token))))
expect_true(grepl("500", resp, fixed = TRUE))

session_end(s)

# --- no stylesheet rule targets something the page never renders ---
#
# The port moved elements from classes to ids, and glinty gives event
# buttons no DOM id at all, so a selector can quietly stop matching
# and nothing notices: CSS fails silently by design.
css <- readLines(system.file("app/www/styles.css", package = "cornfab"),
                 warn = FALSE)
ids_in_page <- unique(gsub('.*id="([^"]*)".*', "\\1",
                           regmatches(html,
                                      gregexpr('id="[^"]*"', html))[[1]]))

sel <- regmatches(css, regexpr("^\\s*#[A-Za-z0-9_-]+", css))
sel <- unique(sub("^\\s*#", "", sel))
expect_true(length(sel) > 0L)
expect_equal(setdiff(sel, ids_in_page), character(0))

# and the routing hooks the stylesheet uses are really emitted
targets <- regmatches(css, gregexpr('\\[data-g-target="[^"]*"\\]', css))[[1]]
for (t in unique(targets)) {
    expect_true(grepl(t, html, fixed = TRUE))
}

# --- no app rule cancels a glinty variant ---
#
# glinty emits `g-btn g-btn-<variant>` and this stylesheet loads after
# glinty's, so a rule on the base class wins at equal specificity and
# cancels every variant. Nothing fails when it happens: the app just
# has one kind of button, which reads as a design choice rather than a
# bug. earshot shipped a column of ghost history rows as gradient pills
# that way.
expect_equal(
  glinty::css_variant_conflicts(
    system.file("app/www/styles.css", package = "cornfab")),
  character(0))
