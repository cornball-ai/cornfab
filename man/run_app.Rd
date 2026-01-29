% tinyrox says don't edit this manually, but it can't stop you!
\name{run_app}
\alias{run_app}
\title{Run the Cornfab App}
\usage{
run_app(host = "0.0.0.0", port = 7803, ...)
}
\arguments{
\item{host}{Host address to bind to. Defaults to "0.0.0.0" for network access.}

\item{port}{Port number. Defaults to 7803.}

\item{...}{Additional arguments passed to shiny::runApp().}
}
\value{
Runs the Shiny app (does not return).
}
\description{
Launch the Cornfab text-to-speech Shiny application.
}
\examples{
\dontrun{
run_app()
run_app(port = 8080)
}

}
