#!/usr/bin/env bash
# Changes the database password in PostgreSQL and in env/database/secrets/, then restarts
# the API, which reads it from there.

set -euo pipefail

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly project_directory

# shellcheck source=lib/env-file.sh
source "${project_directory}/scripts/lib/env-file.sh"


print_usage() {
    cat <<EOF
Usage: $(basename "$0") [-h] [new_password]

Changes the database password in PostgreSQL and in env/database/secrets/,
then restarts the API. The database must be running.

Arguments:
  new_password  The new password, with letters and digits only.
                Generated when omitted, which is recommended: a password given
                here stays in the shell history.

Options:
  -h            Shows this help.

The password is never displayed. It can be read in ${DATABASE_PASSWORD_FILE}.
EOF
}


exit_with_error() {
    local message="$1"

    echo "Error: ${message}" >&2
    echo "See: $(basename "$0") -h" >&2
    exit 1
}


# The password goes unescaped in a connection URL and in the SQL statement below
check_password_format() {
    local password="$1"

    if [[ ! "${password}" =~ ^[A-Za-z0-9]+$ ]]; then
        exit_with_error "the password must only contain letters and digits."
    fi
}


# Once PostgreSQL has changed, a file that cannot be updated would break the API
check_password_file() {
    if [[ ! -w "${DATABASE_PASSWORD_FILE}" ]]; then
        exit_with_error "${DATABASE_PASSWORD_FILE} does not exist or cannot be written."
    fi
}


# Sent through standard input: a command argument would be visible in the process list
change_password_in_postgresql() {
    local new_password="$1"

    printf "ALTER USER CURRENT_USER PASSWORD '%s';\n" "${new_password}" \
        | docker compose exec -T econoris-database \
            sh -c 'psql --quiet -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"'
}


# Only the API: PostgreSQL reads the file at its first start only, and an update of the other
# services must go through deploy.sh. Forced, because Compose does not detect a change in a
# mounted file. The migrations service reads the new password at the next deployment.
restart_api() {
    docker compose up --detach --wait --no-deps --force-recreate econoris-api
}


while getopts ":h" option; do
    case "${option}" in
        h)
            print_usage
            exit 0
            ;;
        *)
            exit_with_error "unknown option -${OPTARG}."
            ;;
    esac
done
shift "$((OPTIND - 1))"

if [[ "$#" -gt 1 ]]; then
    exit_with_error "too many arguments."
fi

password_to_apply="${1:-$(generate_database_password)}"
readonly password_to_apply

check_password_format "${password_to_apply}"

cd "${project_directory}"

check_password_file
change_password_in_postgresql "${password_to_apply}"
write_secret_file "${DATABASE_PASSWORD_FILE}" "${password_to_apply}"
write_migrations_env
restart_api

echo "Database password changed. It can be read in ${DATABASE_PASSWORD_FILE}."
