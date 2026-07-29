#' Run the Cornfab App
#'
#' Launch the Cornfab text-to-speech application.
#'
#' glinty's server listens on all interfaces, so treat the port as
#' reachable from the local network. There is no host argument; bind
#' scoping belongs to the firewall or a reverse proxy.
#'
#' @param port Port number. Defaults to 7803.
#' @param max_upload Largest accepted upload in bytes. Defaults to
#'   64 MB, since reference voice clips routinely exceed glinty's own
#'   10 MB default. Request bodies are buffered whole in memory.
#' @param ... Additional arguments passed to glinty::run_app().
#'
#' @return Runs the app (does not return).
#'
#' @examples
#' \dontrun{
#' run_app()
#' run_app(port = 8080)
#' }
#'
#' @export
run_app <- function(port = 7803, max_upload = 67108864, ...) {
    www <- system.file("app/www", package = "cornfab")
    if (!nzchar(www)) {
        www <- "inst/app/www" # dev mode, before installing
    }
    app <- glinty::app(ui = app_ui(), server = app_server)
    glinty::run_app(app, port = port, static_dir = www,
                    max_upload = max_upload, ...)
}
