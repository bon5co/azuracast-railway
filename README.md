# azuracast-railway

Railway-tuned [AzuraCast](https://www.azuracast.com/) image: the first Super
Administrator account seeded during boot (upstream's setup wizard hands it to
whoever reaches the URL first), all ten persistent paths relocated onto the one
volume Railway attaches, nginx bound to the port Railway's healthcheck dials,
and the php-fpm and InnoDB pools sized from the container's cgroup instead of
upstream's fixed defaults.

Published as `ghcr.io/bon5co/azuracast-railway:latest`, built from
`ghcr.io/azuracast/azuracast:0.23.7`.

## Why each change exists

**The setup wizard authenticates nobody.**
`App\Controller\Frontend\SetupController::registerAction` serves
`GET /setup/register` and accepts its POST from any caller for as long as the
`users` table is empty, and the account it creates carries the Super
Administrator role. Reproduced against the stock image: anonymous
`GET /setup/register` → `200` with a usable CSRF token, anonymous POST → `302`,
`azuracast:account:list` → one Super Administrator nobody deployed. Railway
publishes the HTTPS URL as soon as the deploy is healthy, so that window is
open from then until the deployer opens the page. `railway_seed.php` creates
the account from `AZURACAST_ADMIN_PASSWORD` after the migrations run and before
the site serves traffic; the same probe against this image returns `403`. The
entrypoint refuses to boot at all when the password is empty.

**Ten VOLUMEs, one volume.** The upstream image declares the MariaDB data
directory, station media, backups, uploads and six storage subdirectories as
separate volumes. Railway attaches exactly one, so `railway_volumes.sh`
replaces each path with a symlink into `$RAILWAY_VOLUME_MOUNT_PATH` before any
service starts, and repairs ownership — Railway mounts volumes uid 0 and none
of these services run as root.

**`PORT` vs `AZURACAST_HTTP_PORT`.** Railway injects `PORT` into every service
and it overrides the image's own `ENV`. AzuraCast's nginx template reads
`AZURACAST_HTTP_PORT` and never looks at `PORT`, so without the bridge in
`railway-entrypoint.sh` nginx listens on 80 while Railway's HTTP healthcheck
dials the injected port; the container logs look perfect and the deploy never
goes healthy.

**Pool sizes from the cgroup.** `pm.max_children` is a fixed 20 upstream and
`php.ini` allows each worker 256M, so the pool alone can outgrow a small
container while MariaDB, Liquidsoap and Icecast still need their share;
`innodb_buffer_pool_size` is a fixed 128M however large the container is. Both
are computed from `/sys/fs/cgroup` at boot and both stay overridable — set
`PHP_FPM_MAX_CHILDREN` or `MYSQL_INNODB_BUFFER_POOL_SIZE` yourself and the
entrypoint leaves them alone.

**Pinned.** AzuraCast's database migrations are one-way. A template that builds
`FROM ghcr.io/azuracast/azuracast:latest` on the deployer's build minutes hands
every future redeploy an unrequested version upgrade with no way back.

## Environment

| Variable | Default | Notes |
|---|---|---|
| `AZURACAST_ADMIN_PASSWORD` | — | **Required.** Password for the seeded Super Administrator. The container exits if it is empty. |
| `AZURACAST_ADMIN_EMAIL` | `admin@example.com` | Login identifier for that account; changeable from the UI. |
| `PORT` | `80` | Injected by Railway; becomes `AZURACAST_HTTP_PORT`. |
| `PHP_FPM_MAX_CHILDREN` | sized from cgroup | Set to override. |
| `MYSQL_INNODB_BUFFER_POOL_SIZE` | sized from cgroup | Set to override. |

Every other AzuraCast environment variable behaves as
[upstream documents it](https://www.azuracast.com/docs/administration/docker/).

## Known limits on Railway

- **Live DJ over the Icecast/SHOUTcast source protocol needs a TCP proxy.** A
  Railway service publishes one HTTP domain; listener streams come through
  AzuraCast's own web proxy on that domain (`/listen/...`, on by default), but
  a source client connecting to a station's input port does not. Browser WebDJ
  works over the same domain.
- **SFTP media upload (port 2022) is not exposed** for the same reason. Upload
  through the web UI.
