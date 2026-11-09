# Overleaf Community Edition
FROM sharelatex/sharelatex:6.3.2

# The base image ships a small TeX Live. Set this build arg to "scheme-full"
# (adds several GB and a long build) to get every LaTeX package baked in.
# Packages installed at runtime with tlmgr are lost on every redeploy.
ARG TEXLIVE_SCHEME=""
RUN if [ -n "$TEXLIVE_SCHEME" ]; then \
      tlmgr install "$TEXLIVE_SCHEME" && tlmgr path add; \
    fi

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
