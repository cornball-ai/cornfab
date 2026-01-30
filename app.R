# RStudio "Run App" entrypoint
#
# In dev: loads package code via pkgload::load_all()
# When installed: uses library(cornfab)

# Suppress Shiny's auto R/ loading (we use pkgload instead)
options(shiny.autoload.r = FALSE)

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
} else {
  library(cornfab)
}

shiny::shinyApp(ui = app_ui(), server = app_server)
