# Test cornfab app functions

expect_true(is.function(run_app))
expect_true(is.function(cornfab:::app_ui))
expect_true(is.function(cornfab:::app_server))

# The UI is a component tree, not markup: it travels the wire as
# structure, so a non-browser frontend builds it with real widgets.
ui <- cornfab:::app_ui()
expect_true(inherits(ui, "glinty_component"))
expect_equal(ui$component, "page")
expect_equal(ui$title, "cornfab")
