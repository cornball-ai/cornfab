# Test cornfab app functions

expect_true(is.function(run_app))
expect_true(is.function(cornfab:::app_ui))
expect_true(is.function(cornfab:::app_server))

# Test UI returns a shiny tag
ui <- cornfab:::app_ui()
expect_true(inherits(ui, "shiny.tag") || inherits(ui, "shiny.tag.list"))
