ARG BASETAG=alpine
FROM postgres:$BASETAG

ARG GOCRONVER=v0.0.11
ARG TARGETOS
ARG TARGETARCH
RUN set -x \
	&& apk update && apk add ca-certificates curl \
	&& curl --fail --retry 4 --retry-all-errors -L https://github.com/prodrigestivill/go-cron/releases/download/$GOCRONVER/go-cron-$TARGETOS-$TARGETARCH-static.gz | zcat > /usr/local/bin/go-cron \
	&& chmod a+x /usr/local/bin/go-cron

ENV POSTGRES_DB="**None**" \
    POSTGRES_DB_FILE="**None**" \
    POSTGRES_HOST="**None**" \
    POSTGRES_PORT=5432 \
    POSTGRES_USER="**None**" \
    POSTGRES_USER_FILE="**None**" \
    POSTGRES_PASSWORD="**None**" \
    POSTGRES_PASSWORD_FILE="**None**" \
    POSTGRES_PASSFILE_STORE="**None**" \
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
    WEBHOOK_URL="**None**" \
    WEBHOOK_ERROR_URL="**None**" \
    WEBHOOK_PRE_BACKUP_URL="**None**" \
    WEBHOOK_POST_BACKUP_URL="**None**" \
    WEBHOOK_EXTRA_ARGS=""
    TELEGRAM_BOT_FILE="**None**"
    TELEGRAM_CHAT_FILE="**None**"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""

COPY hooks /hooks
COPY backup.sh env.sh init.sh /

VOLUME /backups

ENTRYPOINT []
CMD ["/init.sh"]

HEALTHCHECK --interval=5m --timeout=3s \
  CMD curl -f "http://localhost:$HEALTHCHECK_PORT/" || exit 1
