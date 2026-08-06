#!/usr/bin/env bash
#
# Repair ownership that the stock startup scripts cannot reach.
#
# 07_sftpgo_conf.sh ends with `chown -R azuracast:azuracast
# /var/azuracast/storage/sftpgo`, but that path is a symlink onto the volume by
# then, and GNU chown -R does not descend through a symlink given as its
# argument. The host keys it just generated therefore stay uid 0 and SFTPGo
# crash-loops with "could not start SFTP server: open .../id_rsa: permission
# denied". Redo the chown on the real directory.
set -u

MOUNT="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
[ -d "$MOUNT/sftpgo" ] || exit 0

chown -R azuracast:azuracast "$MOUNT/sftpgo" 2>/dev/null || true

exit 0
