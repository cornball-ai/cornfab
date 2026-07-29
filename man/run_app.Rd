% tinyrox says don't edit this manually, but it can't stop you!
\name{run_app}
\alias{run_app}
\title{Run the Cornfab App}
\usage{
run_app(port = 7803, max_upload = 67108864, ...)
}
\arguments{
\item{port}{Port number. Defaults to 7803.}

\item{max_upload}{Largest accepted upload in bytes. Defaults to
64 MB, since reference voice clips routinely exceed glinty's own
10 MB default. Request bodies are buffered whole in memory.}

\item{...}{Additional arguments passed to glinty::run_app().}
}
\value{
Runs the app (does not return).
}
\description{
Launch the Cornfab text-to-speech application.
}
\details{
glinty's server listens on all interfaces, so treat the port as
reachable from the local network. There is no host argument; bind
scoping belongs to the firewall or a reverse proxy.

}
\examples{
\dontrun{
run_app()
run_app(port = 8080)
}

}
