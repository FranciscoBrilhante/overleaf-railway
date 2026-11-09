# Overleaf Community Edition
FROM sharelatex/sharelatex:6.3.2

# The base image ships a small TeX Live (2026 in 6.3.2). Bake the full TeX Live
# (scheme-full) into the image: packages installed at runtime with tlmgr are
# lost on every redeploy. Adds several GB and makes the first build slow; this
# step comes first so later edits below reuse the cached layer.
#
# - docfiles/srcfiles 0 skips documentation and sources (about half the download).
# - The live "tlnet" mirror only serves the newest TeX Live year. Once a newer
#   year is released (each spring), "tlmgr update --self" fails with "Local TeX
#   Live is older than remote repository", so fall back to the frozen archive
#   for the installed year.
# - "update --all" brings the base image's packages up to the same revision as
#   the newly installed ones.
# - The install is retried once because mirrors sometimes drop long downloads.
ARG TEXLIVE_MIRROR=https://mirrors.up.pt/pub/CTAN/systems/texlive/tlnet
RUN set -e; \
    tlmgr option docfiles 0; \
    tlmgr option srcfiles 0; \
    tlmgr option repository "$TEXLIVE_MIRROR"; \
    if ! tlmgr update --self; then \
      TL_YEAR=$(tlmgr --version | sed -n 's/.*version \([0-9]\{4\}\).*/\1/p'); \
      echo "Mirror is ahead of TeX Live $TL_YEAR, using the historic archive"; \
      tlmgr option repository "https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/$TL_YEAR/tlnet-final"; \
      tlmgr update --self; \
    fi; \
    tlmgr update --all; \
    tlmgr install scheme-full || tlmgr install scheme-full; \
    tlmgr path add

# Pygments for minted
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-pygments && \
    rm -rf /var/lib/apt/lists/*

# nginx loads every file in sites-enabled/. A stray hotfix .patch file there
# makes "nginx -t" fail and the container crash-loop. Remove any at build
# time, and again at every start (before the nginx step) in case one appears.
RUN rm -f /etc/nginx/sites-enabled/*.patch /etc/nginx/sites-enabled/*.orig /etc/nginx/sites-enabled/*.rej
COPY 150_remove_stray_nginx_files.sh /etc/my_init.d/150_remove_stray_nginx_files.sh
RUN chmod +x /etc/my_init.d/150_remove_stray_nginx_files.sh

# Railway sets PORT in every container. Overleaf's history-v1 service listens
# on $PORT (default 3100) while the other services expect it on 3100, so with
# PORT set, creating projects from examples or zip uploads fails with
# "ECONNREFUSED 127.0.0.1:3100". Clear PORT for that service only.
RUN sed -i '2i unset PORT' /etc/service/history-v1-overleaf/run \
 && grep -q '^unset PORT' /etc/service/history-v1-overleaf/run

# Diagnostic: run "bash /overleaf-check-connections.sh" inside the container
# to test the connections to MongoDB and Redis.
COPY check-connections.sh /overleaf-check-connections.sh

# Overleaf's nginx listens on port 80.
EXPOSE 80
