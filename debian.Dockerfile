ARG BASETAG=latest
FROM postgres:$BASETAG

ARG GOCRONVER=v0.0.11
ARG TARGETOS
ARG TARGETARCH

# Fix Debian cross-build
ARG DEBIAN_FRONTEND=noninteractive
RUN set -x \
    && ln -sf /usr/bin/dpkg-split /usr/sbin/dpkg-split \
    && ln -sf /usr/bin/dpkg-deb /usr/sbin/dpkg-deb \
    && ln -sf /bin/tar /usr/sbin/tar \
    && ln -sf /bin/rm /usr/sbin/rm \
    && ln -sf /usr/bin/dpkg-split /usr/local/sbin/dpkg-split \
    && ln -sf /usr/bin/dpkg-deb /usr/local/sbin/dpkg-deb \
    && ln -sf /bin/tar /usr/local/sbin/tar \
    && ln -sf /bin/rm /usr/local/sbin/rm

# Install required dependencies and download go-cron
RUN set -x \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && curl --fail --retry 4 --retry-all-errors -L "https://github.com/prodrigestivill/go-cron/releases/download/${GOCRONVER}/go-cron-${TARGETOS}-${TARGETARCH}.gz" -o /usr/local/bin/go-cron.gz \
    && gunzip /usr/local/bin/go-cron.gz && chmod a+x /usr/local/bin/go-cron

# Environment Variables
ENV POSTGRES_DB="" \
    POSTGRES_DB_FILE="" \
    POSTGRES_HOST="" \
    POSTGRES_PORT=5432 \
    POSTGRES_USER="" \
    POSTGRES_USER_FILE="" \
    POSTGRES_PASSWORD="" \
    POSTGRES_PASSWORD_FILE="" \
    POSTGRES_PASSFILE_STORE="" \
    POSTGRES_EXTRA_OPTS="-Z1" \
    POSTGRES_CLUSTER="FALSE" \
    SCHEDULE="@daily" \
    VALIDATE_ON_START="TRUE" \
    BACKUP_ON_START="FALSE" \
    BACKUP_DIR="/backups" \
    BACKUP_SUFFIX=".sql.gz" \
    BACKUP_LATEST_TYPE="symlink" \
    BACKUP_KEEP_DAYS=7 \
    BACKUP_KEEP_WEEKS=4 \
    BACKUP_KEEP_MONTHS=6 \
    BACKUP_KEEP_MINS=1440 \
    HEALTHCHECK_PORT=8080 \
    WEBHOOK_URL="" \
    WEBHOOK_ERROR_URL="" \
    WEBHOOK_PRE_BACKUP_URL="" \
    WEBHOOK_POST_BACKUP_URL="" \
    WEBHOOK_EXTRA_ARGS="" \
    TELEGRAM_BOT_TOKEN_FILE="" \
    TELEGRAM_CHAT_ID_FILE="" \
    TELEGRAM_BOT_TOKEN="" \
    TELEGRAM_CHAT_ID=""

# Copy required files
COPY hooks /hooks
COPY backup.sh env.sh init.sh /

# Declare persistent volume for backups
VOLUME /backups

# Set up entrypoint
ENTRYPOINT ["/init.sh"]

# Healthcheck to monitor container
HEALTHCHECK --interval=5m --timeout=3s \
  CMD curl -f "http://localhost:${HEALTHCHECK_PORT}/" || exit 1
