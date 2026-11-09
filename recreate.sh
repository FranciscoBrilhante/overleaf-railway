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
      OVERLEAF_MONGO_URL: mongodb://mongo:27017/sharelatex?directConnection=true
      OVERLEAF_REDIS_HOST: redis
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      OVERLEAF_INVITE_TOKEN_SECRET: ${OVERLEAF_INVITE_TOKEN_SECRET:?set OVERLEAF_INVITE_TOKEN_SECRET in .env}
      ENABLED_LINKED_FILE_TYPES: project_file,project_output_file
      ENABLE_CONVERSIONS: "true"
      EMAIL_CONFIRMATION_DISABLED: "true"
      # Behind an HTTPS proxy (like Railway) also set OVERLEAF_BEHIND_PROXY=true
      # and OVERLEAF_SECURE_COOKIE=true. Don't set OVERLEAF_SECURE_COOKIE at all
      # for plain-http local use: Overleaf enables secure cookies for ANY value,
      # even "false", and then logins fail.

  mongo:
    build: ./mongo
    restart: always
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

   **mongo**: no variables needed.

   **overleaf**
   ```
   OVERLEAF_APP_NAME=Overleaf Community Edition
   OVERLEAF_SITE_URL=https://${{RAILWAY_PUBLIC_DOMAIN}}
   OVERLEAF_MONGO_URL=mongodb://mongo.railway.internal:27017/sharelatex?directConnection=true
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
- **Mongo replica set.** Overleaf needs MongoDB to run as a replica set. The
  `mongo` service sets one up on first boot with the member address
  `localhost:27017`, so it never depends on Railway hostnames. That's why
  `OVERLEAF_MONGO_URL` must end in `?directConnection=true`. Without it,
  Overleaf would try to reach "localhost" and time out.
- **Troubleshooting.** Inside the overleaf container, run
  `bash /overleaf-check-connections.sh` to test MongoDB and Redis.
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
OVERLEAF_EOF

cat > overleaf/150_remove_stray_nginx_files.sh <<'OVERLEAF_EOF'
#!/bin/sh
# Runs at container start, before Overleaf's 200_nginx_config_template.sh.
# nginx loads every file in sites-enabled/, so a stray hotfix .patch file
# there makes "nginx -t" fail and the container crash-loop. Remove them.
echo "[railway-fix] checking /etc/nginx/sites-enabled for non-config files"
for f in /etc/nginx/sites-enabled/*.patch /etc/nginx/sites-enabled/*.orig /etc/nginx/sites-enabled/*.rej; do
  [ -e "$f" ] || continue
  echo "[railway-fix] removing $f"
  rm -f "$f"
done
exit 0
OVERLEAF_EOF

cat > overleaf/check-connections.sh <<'OVERLEAF_EOF'
#!/bin/bash
# Checks whether this Overleaf container can reach MongoDB and Redis.
# Run inside the overleaf container:  bash /overleaf-check-connections.sh
cd /overleaf/services/web && node - <<'JS'
const dns = require('dns').promises
const net = require('net')
const { MongoClient } = require('mongodb')

const mongoUrl = process.env.OVERLEAF_MONGO_URL
const redisHost = process.env.OVERLEAF_REDIS_HOST || process.env.REDIS_HOST
const redisPort = Number(process.env.OVERLEAF_REDIS_PORT || process.env.REDIS_PORT || 6379)
const ok = m => console.log('  OK   ' + m)
const bad = m => console.log('  FAIL ' + m)

function tcp(host, port, family) {
  return new Promise(resolve => {
    const s = net.connect({ host, port, family, timeout: 5000 })
    s.on('connect', () => { s.destroy(); resolve(null) })
    s.on('timeout', () => { s.destroy(); resolve(new Error('timeout')) })
    s.on('error', e => resolve(e))
  })
}

function redisPing(host, port) {
  // family 4 because Overleaf's Redis client (ioredis) only uses IPv4
  return new Promise(resolve => {
    const s = net.connect({ host, port, family: 4, timeout: 5000 })
    let buf = ''
    s.on('connect', () => s.write('PING\r\n'))
    s.on('data', d => { buf += d; s.destroy(); resolve(buf.trim()) })
    s.on('timeout', () => { s.destroy(); resolve('timeout') })
    s.on('error', e => resolve(e.code || e.message))
  })
}

async function checkDns(host) {
  try {
    const all = await dns.lookup(host, { all: true })
    ok(`DNS ${host} -> ${all.map(a => a.address).join(', ')}`)
    if (!all.some(a => a.family === 4)) bad(`${host} has no IPv4 address (Overleaf's Redis client needs IPv4)`)
    return true
  } catch (e) { bad(`DNS ${host}: ${e.code || e.message}`); return false }
}

;(async () => {
  console.log('Environment:')
  console.log('  OVERLEAF_MONGO_URL  =', mongoUrl)
  console.log('  OVERLEAF_REDIS_HOST =', process.env.OVERLEAF_REDIS_HOST)
  console.log('  REDIS_HOST          =', process.env.REDIS_HOST)

  console.log('\nMongoDB:')
  if (!mongoUrl) { bad('OVERLEAF_MONGO_URL is not set') } else {
    const u = new URL(mongoUrl)
    const host = u.hostname, port = Number(u.port || 27017)
    if (await checkDns(host)) {
      const e = await tcp(host, port)
      e ? bad(`TCP ${host}:${port}: ${e.code || e.message}`) : ok(`TCP ${host}:${port} open`)
    }
    // 1) talk to this one server directly, show replica set config
    let c = new MongoClient(mongoUrl, { directConnection: true, serverSelectionTimeoutMS: 5000 })
    try {
      await c.connect()
      const h = await c.db('admin').command({ hello: 1 })
      ok(`connected directly; replica set = ${h.setName || '(none)'}, members = ${JSON.stringify(h.hosts || [])}, primary = ${h.isWritablePrimary}`)
      if (!h.setName) bad('mongod is not running as a replica set (it was not started with --replSet / not initialised)')
      else if (/directConnection=true/i.test(mongoUrl)) ok('OVERLEAF_MONGO_URL uses directConnection=true, so the member address does not need to resolve from here')
      else if (!(h.hosts || []).includes(`${host}:${port}`)) bad(`replica set member is ${JSON.stringify(h.hosts)} but OVERLEAF_MONGO_URL uses ${host}:${port}. Overleaf will try to reach the member address. Add ?directConnection=true to OVERLEAF_MONGO_URL.`)
    } catch (e) { bad(`direct connection: ${e.message}`) } finally { await c.close().catch(() => {}) }
    // 2) connect the way Overleaf does (follows the replica set)
    c = new MongoClient(mongoUrl, { serverSelectionTimeoutMS: 8000 })
    try {
      await c.connect()
      await c.db().command({ ping: 1 })
      ok('connected like Overleaf does (replica set discovery) and ping succeeded')
    } catch (e) { bad(`Overleaf-style connection: ${e.message}`) } finally { await c.close().catch(() => {}) }
  }

  console.log('\nRedis:')
  if (!redisHost) { bad('OVERLEAF_REDIS_HOST / REDIS_HOST not set') } else if (await checkDns(redisHost)) {
    const r = await redisPing(redisHost, redisPort)
    r === '+PONG' ? ok(`PING ${redisHost}:${redisPort} over IPv4 -> PONG`) : bad(`PING ${redisHost}:${redisPort} over IPv4 -> ${r}`)
  }
})()
JS
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
OVERLEAF_EOF

cat > redis/Dockerfile <<'OVERLEAF_EOF'
FROM redis:7.4
EXPOSE 6379
# Listen on IPv4 and (if available) IPv6, persist to /data with AOF.
CMD ["redis-server", "--appendonly", "yes", "--bind", "* -::*", "--protected-mode", "no"]
OVERLEAF_EOF

chmod +x mongo/entrypoint.sh overleaf/150_remove_stray_nginx_files.sh overleaf/check-connections.sh
