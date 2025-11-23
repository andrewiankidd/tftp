#!/bin/sh
set -eu

ROOT="${TFTPD_ROOT:-/var/tftpboot}"
HEALTH_FILE="${TFTPD_HEALTHCHECK_FILE:-.healthcheck}"
MODE="${TFTPD_HEALTHCHECK_MODE:-octet}"
HOST="${TFTPD_HEALTHCHECK_HOST:-127.0.0.1}"
PORT="${TFTPD_HEALTHCHECK_PORT:-69}"
TIMEOUT="${TFTPD_HEALTHCHECK_TIMEOUT:-5}"

touch "${ROOT}/${HEALTH_FILE}"
chmod 0644 "${ROOT}/${HEALTH_FILE}"

if ! pidof in.tftpd >/dev/null 2>&1; then
  exit 1
fi

timeout "${TIMEOUT}" tftp -m "${MODE}" -g -r "${HEALTH_FILE}" -l /dev/null "${HOST}" "${PORT}" >/dev/null 2>&1
