#!/bin/bash

# Configuration
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_USER="udemx"
DB_PASSWORD="Alma1234"
DB_NAME="udemx-db"
BACKUP_ROOT="/srv/mariadb/backup"
DATE_DIR=$(date +'%Y-%m-%d')
BACKUP_DIR="${BACKUP_ROOT}/${DATE_DIR}"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Dump the database
mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
  > "${BACKUP_DIR}/${DB_NAME}.sql"