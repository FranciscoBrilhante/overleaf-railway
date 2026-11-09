#!/bin/bash
# Starts mongod with a replica set and initialises it on first boot.
# The member is registered as localhost:27017, which mongod always accepts as
# itself, so this works no matter what hostname the platform gives us.
# Clients must therefore connect with ?directConnection=true in the URL
# (e.g. mongodb://mongo.railway.internal:27017/sharelatex?directConnection=true)
# so they don't try to reach "localhost" themselves.
set -e
RS_HOST="${MONGO_RS_HOST:-localhost:27017}"
echo "[overleaf] replica set host (MONGO_RS_HOST) = ${RS_HOST}"

(
  until mongosh --quiet --eval 'db.adminCommand({ ping: 1 })' >/dev/null 2>&1; do
    sleep 1
  done
  for attempt in $(seq 1 30); do
    mongosh --quiet --eval "
      try {
        rs.status();
        print('[overleaf] replica set already initialised, members: ' + rs.conf().members.map(m => m.host).join(', '));
      } catch (e) {
        if (e.codeName !== 'NotYetInitialized') throw e;
        rs.initiate({ _id: 'overleaf', members: [{ _id: 0, host: '${RS_HOST}' }] });
        print('[overleaf] replica set initialised with host ${RS_HOST}');
      }" || echo "[overleaf] replica set init attempt ${attempt} failed (see error above)"
    if mongosh --quiet --eval 'quit(db.hello().isWritablePrimary ? 0 : 1)' >/dev/null 2>&1; then
      echo "[overleaf] replica set ready (this node is primary)"
      exit 0
    fi
    sleep 2
  done
  echo "[overleaf] ERROR: replica set still not ready (see errors above)."
) &

# --ipv6 + --bind_ip_all so it is reachable on Railway's private network.
exec docker-entrypoint.sh mongod --replSet overleaf --bind_ip_all --ipv6 "$@"
