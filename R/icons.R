#' Inline SVG icons
#'
#' A small local icon set, replacing shiny::icon()'s FontAwesome
#' dependency. glinty deliberately ships no icons (they are app
#' content, not framework), so cornfab carries the seven shapes it
#' actually uses.
#'
#' Shapes are drawn on a 24x24 grid with a 2px stroke in
#' currentColor, so an icon inherits the colour of whatever contains
#' it. play and stop are filled instead, since outlines read poorly at
#' 16px.
#'
#' @param name character one of "play", "stop", "rotate", "trash",
#'   "microphone", "bookmark", "download"
#' @param size integer pixel size (square)
#' @return A glinty UI element
#'
#' @keywords internal
icon <- function(name, size = 16L) {
    shapes <- icon_shapes(name)
    glinty::tag(
                "svg",
                attrs = list(class = paste0("cf-icon cf-icon-", name),
                             viewBox = "0 0 24 24", width = as.character(size),
                             height = as.character(size), fill = "none",
                             stroke = "currentColor", "stroke-width" = "2",
                             "stroke-linecap" = "round", "stroke-linejoin" = "round",
                             "aria-hidden" = "true"),
                children = shapes
    )
}

#' Child elements for one icon
#'
#' @param name character icon name
#' @return list of glinty UI elements
#'
#' @keywords internal
icon_shapes <- function(name) {
    filled <- function(tag_name, attrs) {
        glinty::tag(tag_name,
                    attrs = c(attrs, list(fill = "currentColor", stroke = "none")))
    }
    line <- function(x1, y1, x2, y2) {
        glinty::tag("line", attrs = list(x1 = x1, y1 = y1, x2 = x2, y2 = y2))
    }

    switch(name,
           play = list(filled("polygon", list(points = "7 4 20 12 7 20"))),
           stop = list(filled("rect", list(x = "6", y = "6", width = "12",
                    height = "12", rx = "2"))),
           rotate = list(
                         glinty::tag("path", attrs = list(d = "M20 12a8 8 0 1 1-2.34-5.66")),
                         glinty::tag("polyline", attrs = list(points = "20 4 20 9 15 9"))
        ),
           trash = list(
                        line("4", "7", "20", "7"),
                        glinty::tag("path", attrs = list(
                    d = "M6 7v12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7")),
                        glinty::tag("path", attrs = list(d = "M9 7V4h6v3")),
                        line("10", "11", "10", "17"),
                        line("14", "11", "14", "17")
        ),
           microphone = list(
                             glinty::tag("rect", attrs = list(x = "9", y = "2", width = "6",
                    height = "11", rx = "3")),
                             glinty::tag("path", attrs = list(d = "M5 11a7 7 0 0 0 14 0")),
                             line("12", "18", "12", "22")
        ),
           bookmark = list(
                           glinty::tag("path", attrs = list(d = "M6 3h12v18l-6-4.5L6 21z"))
        ),
           download = list(
                           line("12", "3", "12", "15"),
                           glinty::tag("polyline", attrs = list(points = "7 10 12 15 17 10")),
                           glinty::tag("path", attrs = list(d = "M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"))
        ),
           stop("unknown icon: ", name, call. = FALSE)
    )
}

#' A button whose label is an icon
#'
#' @param id character input ID
#' @param name character icon name
#' @param title character tooltip and accessible label
#' @param class character extra CSS class(es)
#' @return A glinty UI element
#'
#' @keywords internal
icon_button <- function(id, name, title, class = NULL) {
    glinty::tag(
                "button",
                attrs = list(
                             id = id,
                             class = paste(c("g-btn", "btn-icon", class), collapse = " "),
                             type = "button",
                             title = title,
                             "aria-label" = title
        ),
                children = list(icon(name)),
                bind = list(event = "click", target = id)
    )
}

#' A button with an icon beside its label
#'
#' @param id character input ID
#' @param name character icon name
#' @param label character button text
#' @param class character extra CSS class(es)
#' @return A glinty UI element
#'
#' @keywords internal
icon_label_button <- function(id, name, label, class = NULL) {
    glinty::tag(
                "button",
                attrs = list(
                             id = id,
                             class = paste(c("g-btn", "btn-icon-label", class), collapse = " "),
                             type = "button"
        ),
                children = list(icon(name), glinty::span(label)),
                bind = list(event = "click", target = id)
    )
}
