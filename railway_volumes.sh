#!/usr/bin/env bash
#
# Put everything AzuraCast persists onto the one volume Railway attaches.
#
# The upstream image declares ten separate VOLUMEs -- the MariaDB data
# directory, station media, backups, uploads and six storage subdirectories.
# Railway gives a service exactly one volume, so each of those paths is
# replaced by a symlink into the mount before any service starts. Runs from
# /etc/my_init.d, after 00_setup_user.sh has settled the azuracast uid and
# before 03_persist_dir.sh and 05_setup_db.sh touch any of these paths.
set -u

MOUNT="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"

if [ ! -d "$MOUNT" ]; then
    echo "[railway] no volume mounted at $MOUNT -- station media, the database and"
    echo "[railway] every account will be lost on the next deploy."
    exit 0
fi

relocate() {
    local src="$1" name="$2" owner="$3"
    local dest="$MOUNT/$name"

    [ -L "$src" ] && return 0

    mkdir -p "$dest"

    # First boot: keep whatever the image baked into the original path.
    if [ -d "$src" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        cp -a "$src/." "$dest/" 2>/dev/null || true
    fi

    rm -rf "$src" 2>/dev/null || true
    if [ -e "$src" ]; then
        # Something is mounted here (a plain `docker run` honours the image's
        # VOLUME lines and creates anonymous volumes for all ten). It is
        # already persistent; do not symlink into it.
        echo "[railway] $src is a live mountpoint, leaving it alone"
        return 0
    fi

    mkdir -p "$(dirname "$src")"
    ln -sfn "$dest" "$src"

    # Railway mounts the volume owned by uid 0 and none of these services run
    # as root. Recurse only when the top-level owner is wrong, so a large media
    # library does not get walked on every boot.
    if [ "$(stat -c '%U:%G' "$dest")" != "$owner" ]; then
        chown -R "$owner" "$dest" 2>/dev/null || true
    fi
}

relocate /var/lib/mysql                     mysql        mysql:mysql
relocate /var/azuracast/stations            stations     azuracast:azuracast
relocate /var/azuracast/backups             backups      azuracast:azuracast
relocate /var/azuracast/storage/uploads     uploads      azuracast:azuracast
relocate /var/azuracast/storage/shoutcast2  shoutcast2   azuracast:azuracast
relocate /var/azuracast/storage/stereo_tool stereo_tool  azuracast:azuracast
relocate /var/azuracast/storage/rsas        rsas         azuracast:azuracast
relocate /var/azuracast/storage/geoip       geoip        azuracast:azuracast
relocate /var/azuracast/storage/sftpgo      sftpgo       azuracast:azuracast
relocate /var/azuracast/storage/acme        acme         azuracast:azuracast

echo "[railway] volume $MOUNT owner=$(stat -c '%u:%g' "$MOUNT") relocated=10 paths"

exit 0
