% tinyrox says don't edit this manually, but it can't stop you!
\name{app_ui}
\alias{app_ui}
\title{App UI}
\usage{
app_ui()
}
\value{
A glinty UI tree.
}
\description{
Create the Cornfab app user interface.
}
\details{
Assets are served from inst/app/www under /static/ by run_app().

Built from glinty's component vocabulary rather than from HTML
tags: the tree travels the wire as components, so a non-browser
frontend renders the same app with real widgets. Anything reached
for here that the vocabulary does not supply is a finding against
glinty, not something to paper over with raw markup.

}
\keyword{internal}
