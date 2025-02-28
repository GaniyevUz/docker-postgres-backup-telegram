#!/usr/bin/env bash
set -Eeo pipefail

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
    pg_dumpall -l "${DB}" "${POSTGRES_EXTRA_OPTS}" | gzip > "${FILE}"
  else
    echo "Creating dump of ${DB} database from ${POSTGRES_HOST}..."

    # Check if directory format (-Fd) is used
    if [[ "${POSTGRES_EXTRA_OPTS}" == *"-Fd"* ]]; then
      echo "📂 Directory format (-Fd) detected. Removing compression option (-Z0)..."
      PG_DUMP_OPTS=$(echo "${POSTGRES_EXTRA_OPTS}" | sed 's/-Z0//g' | xargs)
      pg_dump -d "${DB}" -f "${FILE}" "${PG_DUMP_OPTS}"
    else
      pg_dump -d "${DB}" -f "${FILE}" "${POSTGRES_EXTRA_OPTS}"
    fi
  fi


  # Check if the backup file exists and is not empty before proceeding
  if [ -s "${FILE}" ]; then
    echo "✅ Backup file created successfully: ${FILE}"

    # Copy (hardlink) for each entry
    if [ -d "${FILE}" ]; then
        echo "Backup is a directory. Using 'cp -r' instead of 'ln'."
        cp -r "${FILE}" "${DFILE}"
        cp -r "${FILE}" "${WFILE}"
        cp -r "${FILE}" "${MFILE}"
    else
        echo "Replacing daily backup ${DFILE} with the latest backup..."
        ln -vf "${FILE}" "${DFILE}"
        echo "Replacing weekly backup ${WFILE} with the latest backup..."
        ln -vf "${FILE}" "${WFILE}"
        echo "Replacing monthly backup ${MFILE} with the latest backup..."
        ln -vf "${FILE}" "${MFILE}"
    fi

    # Update latest symlinks
    LATEST_LN_ARG=""
    if [ "${BACKUP_LATEST_TYPE}" = "symlink" ]; then
      LATEST_LN_ARG="-s"
    fi
    if [ "${BACKUP_LATEST_TYPE}" = "symlink" ] || [ "${BACKUP_LATEST_TYPE}" = "hardlink" ]; then
      echo "Pointing last backup file to the latest backup..."
      ln "${LATEST_LN_ARG}" -vf "${LAST_FILENAME}" "${BACKUP_DIR}/last/${DB}-latest${BACKUP_SUFFIX}"
      echo "Pointing latest daily backup to the latest backup..."
      ln "${LATEST_LN_ARG}" -vf "${DAILY_FILENAME}" "${BACKUP_DIR}/daily/${DB}-latest${BACKUP_SUFFIX}"
      echo "Pointing latest weekly backup to the latest backup..."
      ln "${LATEST_LN_ARG}" -vf "${WEEKLY_FILENAME}" "${BACKUP_DIR}/weekly/${DB}-latest${BACKUP_SUFFIX}"
      echo "Pointing latest monthly backup to the latest backup..."
      ln "${LATEST_LN_ARG}" -vf "${MONTHLY_FILENAME}" "${BACKUP_DIR}/monthly/${DB}-latest${BACKUP_SUFFIX}"
    else
      echo "Not updating latest backup."
    fi

    # **Send backup to Telegram**
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
    # Ensure KEEP_DAYS, KEEP_WEEKS, KEEP_MONTHS are set correctly
    if [[ -z "${KEEP_DAYS}" || ! "${KEEP_DAYS}" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: KEEP_DAYS is not set or is not a valid number."
      exit 1
    fi

    if [[ -z "${KEEP_WEEKS}" || ! "${KEEP_WEEKS}" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: KEEP_WEEKS is not set or is not a valid number."
      exit 1
    fi

    if [[ -z "${KEEP_MONTHS}" || ! "${KEEP_MONTHS}" =~ ^[0-9]+$ ]]; then
      echo "❌ Error: KEEP_MONTHS is not set or is not a valid number."
      exit 1
    fi
    # Clean old files
    echo "🧹 Cleaning older files for ${DB} database from ${POSTGRES_HOST}..."
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
