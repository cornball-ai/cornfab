FROM rocker/r-ver:4.4

LABEL maintainer="Troy Hernandez <troy@cornball.ai>"
LABEL description="cornfab: Text-to-speech web app (CPU-only UI)"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsodium-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install R packages from CRAN.
# glinty replaces shiny + bslib; its only deps are jsonlite and digest.
RUN install2.r --error --skipinstalled \
    remotes \
    jsonlite \
    digest

# Install cornball-ai packages from GitHub
RUN R -e 'remotes::install_github("cornball-ai/glinty")'
RUN R -e 'remotes::install_github("cornball-ai/tts.api")'
RUN R -e 'remotes::install_github("cornball-ai/cornfab")'

# Create directory for saved voices (mount as volume for persistence)
RUN mkdir -p /root/.cornfab/voices

EXPOSE 7803

CMD ["R", "-e", "cornfab::run_app()"]
