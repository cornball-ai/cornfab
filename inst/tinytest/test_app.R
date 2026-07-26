# Test cornfab app functions

expect_true(is.function(run_app))
expect_true(is.function(cornfab:::app_ui))
expect_true(is.function(cornfab:::app_server))

# The UI is a glinty tag tree, not a shiny tag
ui <- cornfab:::app_ui()
expect_true(inherits(ui, "glinty_tag"))
expect_equal(ui$title, "cornfab")
