# Overleaf Community Edition
FROM sharelatex/sharelatex:6.3.2

# The base image ships a small TeX Live. Set this build arg to "scheme-full"
# (adds several GB and a long build) to get every LaTeX package baked in.
# Packages installed at runtime with tlmgr are lost on every redeploy.
ARG TEXLIVE_SCHEME=""
RUN if [ -n "$TEXLIVE_SCHEME" ]; then \
      tlmgr install "$TEXLIVE_SCHEME" && tlmgr path add; \
    fi

RUN rm -f /etc/nginx/sites-enabled/*.patch /etc/nginx/sites-enabled/*.orig /etc/nginx/sites-enabled/*.rej

COPY 150_remove_stray_nginx_files.sh /etc/my_init.d/150_remove_stray_nginx_files.sh
RUN chmod +x /etc/my_init.d/150_remove_stray_nginx_files.sh

# Overleaf's nginx listens on port 80.
EXPOSE 80
