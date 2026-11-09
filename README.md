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
