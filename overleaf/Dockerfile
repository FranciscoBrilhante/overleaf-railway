# Overleaf Community Edition
FROM sharelatex/sharelatex:6.3.2

# The base image ships a small TeX Live (2026 in 6.3.2). Bake the full TeX Live
# (scheme-full) into the image: packages installed at runtime with tlmgr are
# lost on every redeploy. Adds several GB and makes the first build slow.
#
# The install is split into several RUN steps, one per group of collections,
# so each finished group is a cached layer: if a download fails halfway, the
# next build resumes from the last finished group instead of starting over.
# These steps come first so edits further down reuse all of them.

# Step 1: configure tlmgr and update the base image's packages.
# - docfiles/srcfiles 0 skips documentation and sources (about half the download).
# - The live "tlnet" mirror only serves the newest TeX Live year. Once a newer
#   year is released (each spring), "tlmgr update --self" fails with "Local TeX
#   Live is older than remote repository", so fall back to the frozen archive
#   for the installed year. The chosen repository is saved for later steps.
# - "update --all" brings the base image's packages up to the same revision as
#   the ones installed below.
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
    tlmgr update --all

# tlmgr install with retries
COPY tl-install.sh /usr/local/bin/tl-install
RUN chmod +x /usr/local/bin/tl-install

# Steps 2-8: the collections that make up scheme-full, in groups.
RUN tl-install collection-latexrecommended collection-latexextra \
      collection-fontsrecommended collection-bibtexextra collection-plaingeneric
RUN tl-install collection-mathscience collection-pictures collection-pstricks \
      collection-publishers collection-humanities collection-music collection-games
RUN tl-install collection-luatex collection-xetex collection-metapost \
      collection-fontutils collection-binextra collection-formatsextra
RUN tl-install collection-context
RUN tl-install collection-fontsextra
RUN tl-install collection-langenglish collection-langeuropean collection-langfrench \
      collection-langgerman collection-langitalian collection-langportuguese \
      collection-langspanish collection-langpolish collection-langczechslovak \
      collection-langgreek collection-langcyrillic collection-langarabic \
      collection-langother
RUN tl-install collection-langcjk collection-langchinese collection-langjapanese \
      collection-langkorean

# Step 9: scheme-full itself, which installs anything the groups above missed
# (fast when they all succeeded), then link the binaries into /usr/local/bin.
RUN tl-install scheme-full && tlmgr path add

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
