#!/usr/bin/env bash
# Pre-validate the environment
# shellcheck disable=SC2153
# shellcheck disable=SC2166
if [ "${POSTGRES_DB}" = "**None**" -a "${POSTGRES_DB_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DB or POSTGRES_DB_FILE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=${POSTGRES_PORT_5432_TCP_ADDR}
    POSTGRES_PORT=${POSTGRES_PORT_5432_TCP_PORT}
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

# shellcheck disable=SC2166
if [ "${POSTGRES_USER}" = "**None**" -a "${POSTGRES_USER_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER or POSTGRES_USER_FILE environment variable."
  exit 1
fi

# shellcheck disable=SC2166
if [ "${POSTGRES_PASSWORD}" = "**None**" -a "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD or POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE environment variable or link to a container named POSTGRES."
  exit 1
fi

#Process vars
if [ "${POSTGRES_DB_FILE}" = "**None**" ]; then
  POSTGRES_DBS=$(echo "${POSTGRES_DB}" | tr , " ")
elif [ -r "${POSTGRES_DB_FILE}" ]; then
  # shellcheck disable=SC2034
  POSTGRES_DBS=$(cat "${POSTGRES_DB_FILE}")
else
  echo "Missing POSTGRES_DB_FILE file."
  exit 1
fi
if [ "${POSTGRES_USER_FILE}" = "**None**" ]; then
  export PGUSER="${POSTGRES_USER}"
elif [ -r "${POSTGRES_USER_FILE}" ]; then
  # shellcheck disable=SC2155
  export PGUSER=$(cat "${POSTGRES_USER_FILE}")
else
  echo "Missing POSTGRES_USER_FILE file."
  exit 1
fi
if [ "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
elif [ -r "${POSTGRES_PASSWORD_FILE}" ]; then
  # shellcheck disable=SC2155
  export PGPASSWORD=$(cat "${POSTGRES_PASSWORD_FILE}")
elif [ -r "${POSTGRES_PASSFILE_STORE}" ]; then
  export PGPASSFILE="${POSTGRES_PASSFILE_STORE}"
else
  echo "Missing POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE file."
  exit 1
fi


# Telegram Bot related env
if [ -n "${TELEGRAM_BOT_TOKEN_FILE}" ] && [ -r "${TELEGRAM_BOT_TOKEN_FILE}" ]; then
  # shellcheck disable=SC2155
  export TELEGRAM_BOT_TOKEN=$(cat "${TELEGRAM_BOT_TOKEN_FILE}")
elif [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
else
  echo "❌ Error: TELEGRAM_BOT_TOKEN is not set via environment variable or readable file."
  exit 1
fi

# Check if TELEGRAM_CHAT_ID is provided via file or environment variable
if [ -n "${TELEGRAM_CHAT_ID_FILE}" ] && [ -r "${TELEGRAM_CHAT_ID_FILE}" ]; then
  # shellcheck disable=SC2155
  export TELEGRAM_CHAT_ID=$(cat "${TELEGRAM_CHAT_ID_FILE}")
elif [ -n "${TELEGRAM_CHAT_ID}" ]; then
  export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
else
  echo "❌ Error: TELEGRAM_CHAT_ID is not set via environment variable or readable file."
  exit 1
fi



echo "🔄 Checking Telegram bot credentials..."
# Send a test message to Telegram
echo "📨 Sending test message to Telegram..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
     -d chat_id="${TELEGRAM_CHAT_ID}" \
     -d text="🚀 Container started successfully! Telegram bot credentials are working." \
     -d parse_mode="Markdown")

# Check response
if [[ $RESPONSE == *'"ok":true'* ]]; then
  echo "✅ Telegram message sent successfully!"
else
  echo "❌ Failed to send Telegram message. Response: $RESPONSE"
  exit 1
fi

export PGHOST="${POSTGRES_HOST}"
export PGPORT="${POSTGRES_PORT}"
# shellcheck disable=SC2034
KEEP_MINS=${BACKUP_KEEP_MINS}
# shellcheck disable=SC2034
KEEP_DAYS=${BACKUP_KEEP_DAYS}
# shellcheck disable=SC2034
# shellcheck disable=SC2307
# shellcheck disable=SC2004
# shellcheck disable=SC2006
# shellcheck disable=SC2003
KEEP_WEEKS=`expr $(((${BACKUP_KEEP_WEEKS} * 7) + 1))`
# shellcheck disable=SC2034
# shellcheck disable=SC2307
# shellcheck disable=SC2004
# shellcheck disable=SC2006
# shellcheck disable=SC2003
KEEP_MONTHS=`expr $(((${BACKUP_KEEP_MONTHS} * 31) + 1))`

# Validate backup dir
# shellcheck disable=SC2057
if [ '!' -d "${BACKUP_DIR}" -o '!' -w "${BACKUP_DIR}" -o '!' -x "${BACKUP_DIR}" ]; then
  echo "BACKUP_DIR points to a file or folder with insufficient permissions."
  exit 1
fi
