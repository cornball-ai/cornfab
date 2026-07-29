# RStudio "Run App" entrypoint
#
# In dev: loads package code via pkgload::load_all()
# When installed: uses library(cornfab)

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
} else {
  library(cornfab)
}

run_app()
