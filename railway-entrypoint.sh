#!/usr/bin/env bash
#
# Railway entrypoint for AzuraCast. Runs before the stock `my_init`, so
# everything exported here reaches /container.env and therefore every service
# supervisord starts.
set -eu

if [ -z "${AZURACAST_ADMIN_PASSWORD:-}" ]; then
    cat >&2 <<'MSG'
[railway] AZURACAST_ADMIN_PASSWORD is empty.

AzuraCast's setup wizard creates the first account with no authentication:
SetupController::registerAction serves and accepts POSTs from anybody for as
long as the users table is empty, and the account it creates is a Super
Administrator. Railway publishes the HTTPS URL the moment the deploy goes
healthy, so an instance that boots without a seeded account is claimable by
whoever reaches it first. Set AZURACAST_ADMIN_PASSWORD and redeploy.
MSG
    exit 1
fi

# Railway injects PORT into every service and it overrides the image's own ENV.
# AzuraCast's nginx template reads AZURACAST_HTTP_PORT
# (util/docker/web/nginx/azuracast.conf.tmpl), never PORT, so without this line
# nginx keeps listening on 80 while Railway's HTTP healthcheck dials the
# injected port -- the container looks perfect from inside and the deploy never
# goes healthy.
export AZURACAST_HTTP_PORT="${PORT:-80}"

# Container memory, for sizing the pools below. cgroup v2 first, then v1, then
# the host as a last resort; "max" means no limit was set.
container_memory_mb() {
    local raw=""
    if [ -r /sys/fs/cgroup/memory.max ]; then
        raw="$(cat /sys/fs/cgroup/memory.max)"
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        raw="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    fi

    case "$raw" in
        ''|*[!0-9]*) raw="$(( $(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) ))" ;;
    esac

    echo "$(( raw / 1048576 ))"
}

MEM_MB="$(container_memory_mb)"

# php-fpm's pool is a fixed 20 workers upstream (util/docker/web/php/www.conf.tmpl)
# whatever the container is, and php.ini lets each one reach memory_limit=256M.
# On a small Railway plan that pool alone can outgrow the container while
# MariaDB, Liquidsoap and Icecast still need their share.
if [ -z "${PHP_FPM_MAX_CHILDREN:-}" ]; then
    children=$(( MEM_MB * 40 / 100 / 256 ))
    [ "$children" -lt 4 ] && children=4
    [ "$children" -gt 20 ] && children=20
    export PHP_FPM_MAX_CHILDREN="$children"
fi

# Same shape for InnoDB, in the other direction: 128M is upstream's default no
# matter how much memory the container has.
if [ -z "${MYSQL_INNODB_BUFFER_POOL_SIZE:-}" ]; then
    pool=$(( MEM_MB * 15 / 100 ))
    [ "$pool" -lt 128 ] && pool=128
    [ "$pool" -gt 1024 ] && pool=1024
    export MYSQL_INNODB_BUFFER_POOL_SIZE="${pool}M"
fi

echo "[railway] memory=${MEM_MB}MiB http_port=${AZURACAST_HTTP_PORT}" \
     "php_fpm_max_children=${PHP_FPM_MAX_CHILDREN}" \
     "innodb_buffer_pool_size=${MYSQL_INNODB_BUFFER_POOL_SIZE}"

exec tini -- /usr/local/bin/my_init "$@"
