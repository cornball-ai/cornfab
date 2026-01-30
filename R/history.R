#' History Persistence Functions
#'
#' Functions for managing TTS generation history.
#'
#' @name history
#' @keywords internal
NULL

#' Get history directory
#' @keywords internal
history_dir <- function() {
  dir <- file.path(Sys.getenv("HOME"), ".cornfab")
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  dir
}

#' Get audio directory
#' @keywords internal
audio_dir <- function() {
  dir <- file.path(history_dir(), "audio")
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  dir
}

#' Load history from disk
#' @keywords internal
load_history <- function() {
  path <- file.path(history_dir(), "history.rds")
  if (file.exists(path)) {
    tryCatch(
      readRDS(path),
      error = function(e) list()
    )
  } else {
    list()
  }
}

#' Save history to disk
#' @param history List of history entries.
#' @keywords internal
save_history <- function(history) {
  path <- file.path(history_dir(), "history.rds")
  saveRDS(history, path)
}

#' Create a new history entry
#' @param text Input text.
#' @param voice Voice used.
#' @param backend Backend used.
#' @param model Model used (if any).
#' @param audio_file Path to audio file (optional).
#' @keywords internal
create_history_entry <- function(
  text,
  voice,
  backend,
  model = NULL,
  audio_file = NULL,
  params = NULL
) {
  timestamp <- Sys.time()
  id <- paste0(
    format(timestamp, "%Y%m%d%H%M%S"),
    "_",
    paste0(sample(c(letters, 0:9), 6, replace = TRUE), collapse = "")
  )

  list(
    id = id,
    timestamp = timestamp,
    text = text,
    voice = voice,
    backend = backend,
    model = model,
    audio_file = audio_file,
    params = params
  )
}

#' Add entry to history
#' @param history Current history list.
#' @param entry New entry to add.
#' @keywords internal
add_history_entry <- function(history, entry) {
  c(list(entry), history)
}

#' Delete history entry
#' @param history Current history list.
#' @param id Entry ID to delete.
#' @keywords internal
delete_history_entry <- function(history, id) {
  idx <- which(vapply(history, function(x) x$id == id, logical(1)))
  if (length(idx) > 0) {
    entry <- history[[idx]]
    # Delete associated audio file if it exists
    if (!is.null(entry$audio_file) && file.exists(entry$audio_file)) {
      unlink(entry$audio_file)
    }
    history <- history[-idx]
  }
  history
}

#' Save audio file to history
#' @param audio_data Raw audio bytes.
#' @param entry_id History entry ID.
#' @param format Audio format (wav, mp3).
#' @keywords internal
save_audio_file <- function(audio_data, entry_id, format = "wav") {
  filename <- paste0(entry_id, ".", format)
  path <- file.path(audio_dir(), filename)
  writeBin(audio_data, path)
  path
}

#' Format timestamp for display
#' @param timestamp POSIXct timestamp.
#' @keywords internal
format_timestamp <- function(timestamp) {
  format(timestamp, "%b %d, %H:%M")
}

#' Truncate text for preview
#' @param text Text to truncate.
#' @param max_length Maximum length.
#' @keywords internal
truncate_text <- function(text, max_length = 50) {
  if (nchar(text) <= max_length) {
    text
  } else {
    paste0(substr(text, 1, max_length - 3), "...")
  }
}
