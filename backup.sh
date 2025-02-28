#!/usr/bin/env bash
set -Eeo pipefail

# Define the error handling function
HOOKS_DIR="/hooks"
if [ -d "${HOOKS_DIR}" ]; then
  on_error(){
    run-parts -a "error" "${HOOKS_DIR}"
  }
  trap 'on_error' ERR
fi

source "$(dirname "$0")/env.sh"

# Pre-backup hook
if [ -d "${HOOKS_DIR}" ]; then
  run-parts -a "pre-backup" --exit-on-error "${HOOKS_DIR}"
fi

# Initialize directories
mkdir -p "${BACKUP_DIR}/last/" "${BACKUP_DIR}/daily/" "${BACKUP_DIR}/weekly/" "${BACKUP_DIR}/monthly/"

# Loop through all databases
for DB in ${POSTGRES_DBS}; do
  # Initialize filename versions
  LAST_FILENAME="${DB}-$(date +%Y%m%d-%H%M%S)${BACKUP_SUFFIX}"
  DAILY_FILENAME="${DB}-$(date +%Y%m%d)${BACKUP_SUFFIX}"
  WEEKLY_FILENAME="${DB}-$(date +%G%V)${BACKUP_SUFFIX}"
  MONTHLY_FILENAME="${DB}-$(date +%Y%m)${BACKUP_SUFFIX}"
  FILE="${BACKUP_DIR}/last/${LAST_FILENAME}"
  DFILE="${BACKUP_DIR}/daily/${DAILY_FILENAME}"
  WFILE="${BACKUP_DIR}/weekly/${WEEKLY_FILENAME}"
  MFILE="${BACKUP_DIR}/monthly/${MONTHLY_FILENAME}"

  # Create dump
  if [ "${POSTGRES_CLUSTER}" = "TRUE" ]; then
    echo "Creating cluster dump of ${DB} database from ${POSTGRES_HOST}..."
    if ! pg_dumpall ${POSTGRES_EXTRA_OPTS} | gzip > "${FILE}"; then
      echo "❌ Error: pg_dumpall failed for ${DB}. Skipping backup." >&2
      continue
    fi
  else
    echo "Creating dump of ${DB} database from ${POSTGRES_HOST}..."

    # Check if directory format (-Fd) is used
    if [[ "${POSTGRES_EXTRA_OPTS}" == *"-Fd"* ]]; then
      echo "📂 Directory format (-Fd) detected. Removing compression option (-Z0)..."
      PG_DUMP_OPTS=$(echo "${POSTGRES_EXTRA_OPTS}" | sed 's/-Z0//g' | xargs)
      if ! pg_dump -d "${DB}" -f "${FILE}" ${PG_DUMP_OPTS}; then
        echo "❌ Error: pg_dump failed for ${DB}. Skipping backup." >&2
        continue
      fi
    else
      if ! pg_dump -d "${DB}" -f "${FILE}" "${POSTGRES_EXTRA_OPTS}"; then
        echo "❌ Error: pg_dump failed for ${DB}. Skipping backup." >&2
        continue
      fi
    fi
  fi

  # Check if the backup file exists and is not empty before proceeding
  if [ -s "${FILE}" ]; then
    echo "✅ Backup file created successfully: ${FILE}"

    # Replace or copy backups
    ln -vf "${FILE}" "${DFILE}"
    ln -vf "${FILE}" "${WFILE}"
    ln -vf "${FILE}" "${MFILE}"

    # Update latest symlinks
    LATEST_LN_ARG=""
    if [ "${BACKUP_LATEST_TYPE}" = "symlink" ]; then
      LATEST_LN_ARG="-s"
    fi
    if [ "${BACKUP_LATEST_TYPE}" = "symlink" ] || [ "${BACKUP_LATEST_TYPE}" = "hardlink" ]; then
      ln "${LATEST_LN_ARG}" -vf "${LAST_FILENAME}" "${BACKUP_DIR}/last/${DB}-latest${BACKUP_SUFFIX}"
      ln "${LATEST_LN_ARG}" -vf "${DAILY_FILENAME}" "${BACKUP_DIR}/daily/${DB}-latest${BACKUP_SUFFIX}"
      ln "${LATEST_LN_ARG}" -vf "${WEEKLY_FILENAME}" "${BACKUP_DIR}/weekly/${DB}-latest${BACKUP_SUFFIX}"
      ln "${LATEST_LN_ARG}" -vf "${MONTHLY_FILENAME}" "${BACKUP_DIR}/monthly/${DB}-latest${BACKUP_SUFFIX}"
    else
      echo "Not updating latest backup."
    fi

    # Send backup to Telegram
    if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]]; then
      echo "📤 Sending backup file to Telegram..."
      curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TELEGRAM_CHAT_ID}" \
        -F document=@"${FILE}" \
        -F caption="📂 PostgreSQL Backup: ${DB} ($(date +'%Y-%m-%d %H:%M:%S'))"

      echo "✅ Backup file sent to Telegram successfully!"
    else
      echo "⚠️ Telegram credentials not provided. Skipping Telegram upload."
    fi

    # Clean old files based on KEEP_DAYS, KEEP_WEEKS, KEEP_MONTHS
    echo "🧹 Cleaning older files for ${DB}..."
    find "${BACKUP_DIR}/last" -maxdepth 1 -mmin "+${KEEP_MINS}" -name "${DB}-*${BACKUP_SUFFIX}" -exec rm -rvf '{}' ';'
    find "${BACKUP_DIR}/daily" -maxdepth 1 -mtime "+${KEEP_DAYS}" -name "${DB}-*${BACKUP_SUFFIX}" -exec rm -rvf '{}' ';'
    find "${BACKUP_DIR}/weekly" -maxdepth 1 -mtime "+${KEEP_WEEKS}" -name "${DB}-*${BACKUP_SUFFIX}" -exec rm -rvf '{}' ';'
    find "${BACKUP_DIR}/monthly" -maxdepth 1 -mtime "+${KEEP_MONTHS}" -name "${DB}-*${BACKUP_SUFFIX}" -exec rm -rvf '{}' ';'
  else
    echo "❌ Error: Backup file ${FILE} is empty or missing. Skipping Telegram upload."
  fi
done

echo "✅ SQL backup process completed successfully."

# Post-backup hook
if [ -d "${HOOKS_DIR}" ]; then
  run-parts -a "post-backup" --reverse --exit-on-error "${HOOKS_DIR}"
fi
