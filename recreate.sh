mkdir -p overleaf-railway/{overleaf,mongo,redis} && cd overleaf-railway

cat > docker-compose.yml <<'OVERLEAF_EOF'
# Overleaf Community Edition: overleaf + mongo (replica set) + redis.
# Locally:   cp .env.example .env  (fill it in)  &&  docker compose up -d --build
# Railway:   see README.md (each folder becomes one Railway service).

services:
  overleaf:
    build:
      context: ./overleaf
      args:
        TEXLIVE_SCHEME: ${TEXLIVE_SCHEME:-}
    restart: always
    depends_on:
      mongo:
        condition: service_healthy
      redis:
        condition: service_started
    ports:
      - "${OVERLEAF_PORT:-8080}:80"
    stop_grace_period: 60s
    volumes:
      - overleaf_data:/var/lib/overleaf
    environment:
      OVERLEAF_APP_NAME: ${OVERLEAF_APP_NAME:-Overleaf Community Edition}
      OVERLEAF_SITE_URL: ${OVERLEAF_SITE_URL:-http://localhost:8080}
      OVERLEAF_MONGO_URL: mongodb://mongo:27017/sharelatex
      OVERLEAF_REDIS_HOST: redis
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      OVERLEAF_INVITE_TOKEN_SECRET: ${OVERLEAF_INVITE_TOKEN_SECRET:?set OVERLEAF_INVITE_TOKEN_SECRET in .env}
      ENABLED_LINKED_FILE_TYPES: project_file,project_output_file
      ENABLE_CONVERSIONS: "true"
      EMAIL_CONFIRMATION_DISABLED: "true"
      OVERLEAF_BEHIND_PROXY: ${OVERLEAF_BEHIND_PROXY:-false}
      OVERLEAF_SECURE_COOKIE: ${OVERLEAF_SECURE_COOKIE:-false}

  mongo:
    build: ./mongo
    restart: always
    environment:
      MONGO_RS_HOST: mongo:27017
    volumes:
      - mongo_data:/data/db
    healthcheck:
      # Healthy only once the replica set has a primary.
      test: ["CMD", "mongosh", "--quiet", "--eval", "quit(db.hello().isWritablePrimary ? 0 : 1)"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 20s

  redis:
    build: ./redis
    restart: always
    volumes:
      - redis_data:/data

volumes:
  overleaf_data:
  mongo_data:
  redis_data:
OVERLEAF_EOF

cat > .env.example <<'OVERLEAF_EOF'
# Generate with: openssl rand -base64 32
OVERLEAF_INVITE_TOKEN_SECRET=
OVERLEAF_APP_NAME=Overleaf Community Edition
OVERLEAF_SITE_URL=http://localhost:8080
OVERLEAF_PORT=8080
# Set to scheme-full to bake the full TeX Live into the image (big, slow build)
TEXLIVE_SCHEME=
OVERLEAF_EOF

cat > .gitignore <<'OVERLEAF_EOF'
.env
OVERLEAF_EOF

cat > README.md <<'OVERLEAF_EOF'
# Overleaf Community Edition on Railway

Three services, each built from its own folder:

| Folder      | Image                          | Purpose                               | Volume mount       |
|-------------|--------------------------------|---------------------------------------|--------------------|
| `overleaf/` | `sharelatex/sharelatex:6.3.2`  | Overleaf web app (port 80)            | `/var/lib/overleaf`|
| `mongo/`    | `mongo:8.0`                    | MongoDB as a single-node replica set  | `/data/db`         |
| `redis/`    | `redis:7.4`                    | Redis with AOF persistence            | `/data`            |

## Run locally

```bash
cp .env.example .env
```
Put the output of `openssl rand -base64 32` in `OVERLEAF_INVITE_TOKEN_SECRET`.
```bash
docker compose up -d --build
```
Open http://localhost:8080/launchpad to create the first admin account.

## Deploy to Railway

Railway runs each container as a separate service rather than running
`docker compose` itself, so you create one service per folder.

1. Push this folder to a GitHub repo.
2. In a new Railway project, add three services with **New → GitHub Repo**,
   picking this repo each time. Name them exactly **`mongo`**, **`redis`** and
   **`overleaf`** (the names become the private hostnames
   `mongo.railway.internal` etc.).
3. For each service, open **Settings → Source → Root Directory** and set it to
   `/mongo`, `/redis` or `/overleaf`. Railway picks up the Dockerfile there.
4. Add a **volume** to each service (right-click the service → Attach volume):
   - `mongo` → `/data/db`
   - `redis` → `/data`
   - `overleaf` → `/var/lib/overleaf`
5. Set the **variables**:

   **mongo**
   ```
   MONGO_RS_HOST=mongo.railway.internal:27017
   ```

   **overleaf**
   ```
   OVERLEAF_APP_NAME=Overleaf Community Edition
   OVERLEAF_SITE_URL=https://${{RAILWAY_PUBLIC_DOMAIN}}
   OVERLEAF_MONGO_URL=mongodb://mongo.railway.internal:27017/sharelatex
   OVERLEAF_REDIS_HOST=redis.railway.internal
   REDIS_HOST=redis.railway.internal
   REDIS_PORT=6379
   OVERLEAF_INVITE_TOKEN_SECRET=<output of: openssl rand -base64 32>
   OVERLEAF_BEHIND_PROXY=true
   OVERLEAF_SECURE_COOKIE=true
   ENABLED_LINKED_FILE_TYPES=project_file,project_output_file
   ENABLE_CONVERSIONS=true
   EMAIL_CONFIRMATION_DISABLED=true
   ```
   Optional for `overleaf`: `TEXLIVE_SCHEME=scheme-full` bakes the full TeX
   Live into the image. Builds take much longer and the image grows by several
   GB, but packages installed later with `tlmgr` would be lost on every
   redeploy.

6. On the `overleaf` service, go to **Settings → Networking → Generate Domain**
   and set the **target port to 80**. Leave `mongo` and `redis` without public
   domains.
7. Deploy `mongo` and `redis` first, then `overleaf`. Its first start takes a
   couple of minutes. Then open `https://<your-domain>/launchpad` to create the
   admin account.

### Notes
- **Mongo hostname is persistent.** The replica set is initialised once with
  `MONGO_RS_HOST` and saved in the volume. If you rename the `mongo` service
  later, you need to reconfigure the replica set (`rs.reconfig`) or wipe the
  volume.
- **IPv4 private networking.** Overleaf's Redis client only connects over IPv4.
  Current Railway environments are dual-stack. Older environments with an
  IPv6-only private network fail with `ENOTFOUND redis.railway.internal`
  errors. In that case, deploy into a newly created environment or project.
- **Resources.** Give `overleaf` at least 2 GB RAM. Compiles are CPU-heavy.
- **Security.** Community Edition has no compile sandboxing, so users can run
  arbitrary code through LaTeX. Only invite people you trust.
- **Email** (invites, password resets): add the `OVERLEAF_EMAIL_SMTP_*`
  variables from the
  [Overleaf docs](https://github.com/overleaf/overleaf/wiki).
- **Upgrades:** bump the tag in `overleaf/Dockerfile` and read Overleaf's
  release notes first, since some major versions need data migrations.
OVERLEAF_EOF

cat > overleaf/Dockerfile <<'OVERLEAF_EOF'
# Overleaf Community Edition
FROM sharelatex/sharelatex:6.3.2

# The base image ships a small TeX Live. Set this build arg to "scheme-full"
# (adds several GB and a long build) to get every LaTeX package baked in.
# Packages installed at runtime with tlmgr are lost on every redeploy.
ARG TEXLIVE_SCHEME=""
RUN if [ -n "$TEXLIVE_SCHEME" ]; then \
      tlmgr install "$TEXLIVE_SCHEME" && tlmgr path add; \
    fi

# Overleaf's nginx listens on port 80.
EXPOSE 80
OVERLEAF_EOF

cat > mongo/Dockerfile <<'OVERLEAF_EOF'
# MongoDB as a single-node replica set (Overleaf requires a replica set)
FROM mongo:8.0
COPY entrypoint.sh /usr/local/bin/overleaf-mongo-entrypoint.sh
RUN chmod +x /usr/local/bin/overleaf-mongo-entrypoint.sh
EXPOSE 27017
ENTRYPOINT ["/usr/local/bin/overleaf-mongo-entrypoint.sh"]
OVERLEAF_EOF

cat > mongo/entrypoint.sh <<'OVERLEAF_EOF'
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
OVERLEAF_EOF

cat > redis/Dockerfile <<'OVERLEAF_EOF'
FROM redis:7.4
EXPOSE 6379
# Listen on IPv4 and (if available) IPv6, persist to /data with AOF.
CMD ["redis-server", "--appendonly", "yes", "--bind", "* -::*", "--protected-mode", "no"]
OVERLEAF_EOF

chmod +x mongo/entrypoint.sh

