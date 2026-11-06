#!/usr/bin/env bash
# Writes an encrypted, compressed dump of the running database to backups/, then removes the
# oldest ones. Only a public key is on this server: it can write backups, but not read them.

set -euo pipefail

readonly BACKUP_RETENTION_COUNT="${BACKUP_RETENTION_COUNT:-30}"

# With an explicit project name, Compose does not read the files of the repositories on
# GitHub, so a backup still works when GitHub is down
readonly COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-econoris}"

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_directory
readonly backup_directory="${project_directory}/backups"

backup_file="${backup_directory}/econoris_$(date +%Y-%m-%d_%H-%M-%S).sql.gz.age"
readonly backup_file

# shellcheck source=lib/env-file.sh
source "${project_directory}/scripts/lib/env-file.sh"


remove_oldest_backups() {
    find "${backup_directory}" -maxdepth 1 -name 'econoris_*.sql.gz.age' -printf '%f\n' \
        | sort -r \
        | tail -n +"$((BACKUP_RETENTION_COUNT + 1))" \
        | while read -r outdated_backup; do
            rm -f -- "${backup_directory}/${outdated_backup}"
        done
}


cd "${project_directory}"

# Without this check, the database would be dumped for nothing. A backup is never written
# unencrypted, even as a fallback: it holds personal financial data.
if ! can_encrypt_backups; then
    echo "Error: ${BACKUP_ENCRYPTION_REQUIREMENT}" >&2
    exit 1
fi

# Encryption protects the content: these permissions also keep the dates and sizes private
umask 077
mkdir -p "${backup_directory}"

# A truncated dump must never pass for a valid backup
trap 'rm -f -- "${backup_file}"' ERR

# Without the privileges: they name the role of the API, which a new empty database does not have
# yet, so the restoration would fail. econoris-api-role grants them again at the next deployment.
docker compose --project-name "${COMPOSE_PROJECT}" exec -T econoris-database \
    sh -c 'pg_dump --no-privileges -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"' \
    | gzip \
    | age --encrypt --recipients-file "${BACKUP_RECIPIENTS_FILE}" \
    > "${backup_file}"

trap - ERR

remove_oldest_backups

echo "Backup written: ${backup_file}"
