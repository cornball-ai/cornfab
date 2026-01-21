#' Run the Cornfab App
#'
#' Launch the Cornfab text-to-speech Shiny application.
#'
#' @param host Host address to bind to. Defaults to "0.0.0.0" for network access.
#' @param port Port number. Defaults to 7803.
#' @param ... Additional arguments passed to shiny::runApp().
#'
#' @return Runs the Shiny app (does not return).
#'
#' @examples
#' \dontrun{
#' run_app()
#' run_app(port = 8080)
#' }
#'
#' @export
run_app <- function(
  host = "0.0.0.0",
  port = 7803,
  ...
) {
  app <- shiny::shinyApp(ui = app_ui(), server = app_server)
  shiny::runApp(app, host = host, port = port, ...)
}

