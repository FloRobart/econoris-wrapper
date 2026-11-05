#!/usr/bin/env bash
# Keeps env/ in line with the .env.example of the latest release of each repository:
#   - a missing .env is created from that example, with the production values below;
#   - an existing .env is never modified, but a variable it lacks is reported;
#   - backups that could not be encrypted are reported.
#
# Exits with status 1 when something needs a look, so a deployment stops before it starts.

set -euo pipefail

readonly GITHUB_FILES_URL="https://raw.githubusercontent.com/FloRobart"

# Same branch as the includes of docker-compose.yml
readonly RELEASE_BRANCH="main"

readonly APP_PUBLIC_URL="https://app.econoris.fr"
readonly API_PUBLIC_URL="https://api.econoris.fr"
readonly AUTH_PUBLIC_URL="https://api.floraccess.florobart.fr"

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_directory

# shellcheck source=lib/env-file.sh
source "${project_directory}/scripts/lib/env-file.sh"

temporary_directory="$(mktemp -d)"
readonly temporary_directory
trap 'rm -rf -- "${temporary_directory}"' EXIT

needs_review=false


configure_proxy() {
    local env_file="$1"

    echo "To fill in by hand: LETSENCRYPT_EMAIL in ${env_file}"
}


configure_database() {
    write_secret_file "${DATABASE_PASSWORD_FILE}" "$(generate_database_password)"
}


configure_api() {
    local env_file="$1"

    set_env_value "${env_file}" APP_ENV prod
    set_env_value "${env_file}" BASE_URL "${API_PUBLIC_URL}"
    set_env_value "${env_file}" AUTH_APP_URL "${AUTH_PUBLIC_URL}"
    set_env_value "${env_file}" CORS_ALLOWED_ORIGINS "${APP_PUBLIC_URL}"
}


configure_app() {
    local env_file="$1"

    set_env_value "${env_file}" AUTH_URL "${AUTH_PUBLIC_URL}"
    set_env_value "${env_file}" DATA_URL "${API_PUBLIC_URL}"

    # nginx serves this file to every visitor, from a user that must be able to read it
    chmod 644 "${env_file}"
}


create_env_file() {
    local env_name="$1"
    local example_file="$2"
    local env_file="env/${env_name}/.env"

    mkdir -p "env/${env_name}"
    install -m 600 "${example_file}" "${env_file}"
    "configure_${env_name}" "${env_file}"

    echo "Created: ${env_file}"
    needs_review=true
}


report_missing_variables() {
    local env_file="$1"
    local example_file="$2"
    local variable_name

    while read -r variable_name; do
        if ! grep -q "^${variable_name}=" "${env_file}"; then
            echo "Missing in ${env_file}: ${variable_name}"
            needs_review=true
        fi
    done < <(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "${example_file}")
}


sync_env_file() {
    local env_name="$1"
    local repository="$2"
    local example_file="${temporary_directory}/${env_name}.env.example"

    curl --fail --silent --show-error --location --output "${example_file}" \
        "${GITHUB_FILES_URL}/${repository}/${RELEASE_BRANCH}/.env.example"

    if [[ -f "env/${env_name}/.env" ]]; then
        report_missing_variables "env/${env_name}/.env" "${example_file}"
        return
    fi

    create_env_file "${env_name}" "${example_file}"
}


cd "${project_directory}"

sync_env_file proxy econoris-proxy
sync_env_file database econoris-database
sync_env_file api econoris-api
sync_env_file app econoris-app

write_migrations_env

# A deployment backs up the database: better to find out before anything is touched
if ! can_encrypt_backups; then
    echo "To fix: ${BACKUP_ENCRYPTION_REQUIREMENT}"
    needs_review=true
fi

if [[ "${needs_review}" == true ]]; then
    echo "Review env/, then run the command again."
    exit 1
fi
