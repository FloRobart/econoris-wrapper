#!/usr/bin/env bash
# Helpers to edit the configuration of env/. This file is sourced by the other scripts,
# which run from the root of this repository.

readonly DATABASE_ENV_FILE="env/database/.env"
readonly DATABASE_PASSWORD_FILE="env/database/secrets/db_password"
readonly MIGRATIONS_ENV_FILE="env/database/secrets/migrations.env"

# Created by econoris-api-role of econoris-database, which applies this password on every deployment
readonly API_DATABASE_ROLE="econoris_api"
readonly API_DATABASE_PASSWORD_FILE="env/database/secrets/api_db_password"

readonly BACKUP_RECIPIENTS_FILE="env/backup-recipients.txt"
readonly BACKUP_ENCRYPTION_REQUIREMENT="backups need age to be installed and an age public key in ${BACKUP_RECIPIENTS_FILE}"


set_env_value() {
    local env_file="$1"
    local variable_name="$2"
    local value="$3"

    sed -i "s|^${variable_name}=.*|${variable_name}=${value}|" "${env_file}"
}


read_env_value() {
    local env_file="$1"
    local variable_name="$2"

    sed -n "s/^${variable_name}=//p" "${env_file}"
}


# Letters and digits only: the password goes unescaped in a connection URL and in SQL statements
generate_database_password() {
    openssl rand -hex 32
}


# Each container reads its secrets with its own unprivileged user, so the file must be readable
# by everyone. The directory is what protects it on the host: containers do not go through it.
write_secret_file() {
    local secret_file="$1"
    local secret_value="$2"

    install -d -m 700 "$(dirname "${secret_file}")"
    printf '%s\n' "${secret_value}" > "${secret_file}"
    chmod 644 "${secret_file}"
}


# A trial encryption, because age alone can tell whether a key is valid. It also refuses a
# private key pasted by mistake, which must never be on this server.
can_encrypt_backups() {
    age --encrypt --recipients-file "${BACKUP_RECIPIENTS_FILE}" < /dev/null > /dev/null 2>&1
}

# Only made of other values, and written again on each run, so it can never drift from them
write_migrations_env() {
    local database_user
    local database_name
    local database_password

    database_user="$(read_env_value "${DATABASE_ENV_FILE}" DB_USER)"
    database_name="$(read_env_value "${DATABASE_ENV_FILE}" DB_NAME)"
    database_password="$(cat "${DATABASE_PASSWORD_FILE}")"

    write_secret_file "${MIGRATIONS_ENV_FILE}" \
        "DATABASE_URL=postgres://${database_user}:${database_password}@econoris-database:5432/${database_name}?sslmode=disable"
}
