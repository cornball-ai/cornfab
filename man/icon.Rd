% tinyrox says don't edit this manually, but it can't stop you!
\name{icon}
\alias{icon}
\title{Inline SVG icons}
\usage{
icon(name, size = 16L)
}
\arguments{
\item{name}{character one of "play", "stop", "rotate", "trash",
"microphone", "bookmark", "download"}

\item{size}{integer pixel size (square)}
}
\value{
A glinty UI element
}
\description{
A small local icon set, replacing shiny::icon()'s FontAwesome
dependency. glinty deliberately ships no icons (they are app
content, not framework), so cornfab carries the seven shapes it
actually uses.
}
\details{
Shapes are drawn on a 24x24 grid with a 2px stroke in
currentColor, so an icon inherits the colour of whatever contains
it. play and stop are filled instead, since outlines read poorly at
16px.

}
\keyword{internal}
