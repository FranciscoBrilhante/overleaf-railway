#!/bin/sh
# Installs TeX Live packages with tlmgr, retrying up to 3 times because mirrors
# sometimes drop long downloads. Used by the Dockerfile, one RUN per group.
for attempt in 1 2 3; do
  tlmgr install "$@" && exit 0
  echo "[tl-install] attempt $attempt failed, retrying in 10s"
  sleep 10
done
exit 1
