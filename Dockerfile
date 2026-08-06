# AzuraCast for Railway.
#
# AzuraCast ships as one all-in-one container -- nginx, php-fpm, MariaDB,
# Redis, Icecast, Liquidsoap, SFTPGo and a cron runner under supervisord -- so
# the whole radio station is a single Railway service. What it does not ship is
# anything that knows about Railway, and three of those gaps are load-bearing:
#
#   1. The setup wizard hands out the first Super Administrator account to
#      whoever asks. App\Controller\Frontend\SetupController::registerAction
#      serves GET /setup/register and accepts its POST with no authentication
#      of any kind for as long as the users table is empty, and Railway
#      publishes the HTTPS URL as soon as the deploy goes healthy -- normally
#      minutes before the deployer opens it. This image seeds the account
#      during boot from AZURACAST_ADMIN_PASSWORD and refuses to start without
#      one, so the window is closed before the site answers a request.
#   2. Ten VOLUME paths, one Railway volume. railway_volumes.sh relocates all
#      ten onto the mount before any service starts.
#   3. nginx listens on AZURACAST_HTTP_PORT, and Railway's healthcheck dials
#      the PORT it injects. railway-entrypoint.sh bridges the two.
#
# Pinned, and built here rather than on the deployer's build minutes: the tag
# is a ~4 GB image and AzuraCast's database migrations are one-way, so a
# template that builds FROM :latest hands every future redeploy a version
# upgrade that cannot be rolled back.
FROM ghcr.io/azuracast/azuracast:0.23.7

# Baked, NOT published as template variables: templateGenerate keeps a
# variable's defaultValue only when the live value is a Railway expression, so
# a literal publishes as a blank REQUIRED field on the deploy form.
#
#   ENABLE_WEB_UPDATER   the in-app updater drives a sidecar container over
#                        docker.sock; neither exists here. Update by bumping
#                        the pinned tag and redeploying.
#   MYSQL_RANDOM_ROOT_PASSWORD
#                        MariaDB is bound to localhost inside this container
#                        and only the `azuracast` user is ever used, so the
#                        root password does not need to be a deploy-form field.
#   AZURACAST_ADMIN_EMAIL
#                        login identifier for the seeded account; changeable
#                        from the UI afterwards.
ENV ENABLE_WEB_UPDATER=false \
    MYSQL_RANDOM_ROOT_PASSWORD=yes \
    AZURACAST_ADMIN_EMAIL=admin@example.com

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY railway_app_startup /usr/local/bin/railway_app_startup
COPY railway_seed.php /usr/local/bin/railway_seed.php
COPY railway_volumes.sh /etc/my_init.d/01_railway_volumes.sh
COPY railway_fixups.sh /etc/my_init.d/09_railway_fixups.sh

RUN chmod +x /usr/local/bin/railway-entrypoint.sh \
             /usr/local/bin/railway_app_startup \
             /etc/my_init.d/01_railway_volumes.sh \
             /etc/my_init.d/09_railway_fixups.sh \
    # supervisord's `startup` program runs the stock app_startup; point it at
    # the wrapper that also seeds the administrator once the database is up.
    && sed -i 's/^command=app_startup$/command=railway_app_startup/' \
             /etc/supervisor/full.conf.d/startup.conf \
    && grep -q '^command=railway_app_startup$' /etc/supervisor/full.conf.d/startup.conf

# A derived ENTRYPOINT resets the base image's CMD, so restate it.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["--no-main-command"]
