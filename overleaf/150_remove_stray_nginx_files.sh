#!/bin/sh
# Runs at container start, before Overleaf's 200_nginx_config_template.sh.
echo "[railway-fix] checking /etc/nginx/sites-enabled for non-config files"
for f in /etc/nginx/sites-enabled/*.patch /etc/nginx/sites-enabled/*.orig /etc/nginx/sites-enabled/*.rej; do
  [ -e "$f" ] || continue
  echo "[railway-fix] removing $f"
  rm -f "$f"
done
exit 0