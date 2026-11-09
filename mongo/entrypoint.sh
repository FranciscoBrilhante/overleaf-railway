#!/bin/bash
# Starts mongod with a replica set and initialises it on first boot.
# MONGO_RS_HOST must be the address other services use to reach this
# container: "mongo:27017" in docker compose, "mongo.railway.internal:27017"
# on Railway (if the Railway service is named "mongo").
set -e
RS_HOST="${MONGO_RS_HOST:-mongo:27017}"

(
  until mongosh --quiet --eval 'db.adminCommand({ ping: 1 })' >/dev/null 2>&1; do
    sleep 1
  done
  mongosh --quiet --eval "
    try {
      rs.status();
      print('[overleaf] replica set already initialised');
    } catch (e) {
      rs.initiate({ _id: 'overleaf', members: [{ _id: 0, host: '${RS_HOST}' }] });
      print('[overleaf] replica set initialised with host ${RS_HOST}');
    }"
) &

# --ipv6 + --bind_ip_all so it is reachable on Railway's private network.
exec docker-entrypoint.sh mongod --replSet overleaf --bind_ip_all --ipv6 "$@"
