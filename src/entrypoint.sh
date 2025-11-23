#!/bin/sh
set -e

# Escape single quotes so we can safely eval-append arguments later.
escape_arg() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

# Standardized logging helpers.
log() {
  printf '[entrypoint] %s\n' "$*"
}

log_error() {
  printf '[entrypoint][error] %s\n' "$*" >&2
}

entrypoint_error() {
  status="$1"
  line="$2"
  context="$3"
  if [ -n "$context" ]; then
    log_error "Failure during ${context} (exit ${status}) at line ${line}"
  else
    log_error "Failure (exit ${status}) at line ${line}"
  fi
  exit "$status"
}

CURRENT_STAGE="initialization"
trap 'entrypoint_error $? $LINENO "$CURRENT_STAGE"' ERR

# Trim leading/trailing whitespace from list entries.
trim_spaces() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Append a single argument to TFTPD_ARGS, keeping shell-safe quoting.
append_arg() {
  if [ -z "$1" ]; then
    return
  fi
  escaped="$(escape_arg "$1")"
  if [ -z "$TFTPD_ARGS" ]; then
    TFTPD_ARGS="'$escaped'"
  else
    TFTPD_ARGS="$TFTPD_ARGS '$escaped'"
  fi
}

is_enabled() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

append_flag_if_enabled() {
  value="$1"
  flag="$2"
  if is_enabled "$value"; then
    append_arg "$flag"
  fi
}

append_arg_with_value() {
  flag="$1"
  value="$2"
  if [ -n "$value" ]; then
    append_arg "$flag"
    append_arg "$value"
  fi
}

# Append comma or newline separated items, optionally prefixed with flag.
append_list_items() {
  flag="$1"
  items="$2"
  if [ -z "$items" ]; then
    return
  fi
  while IFS= read -r entry; do
    entry="$(trim_spaces "$entry")"
    if [ -z "$entry" ]; then
      continue
    fi
    if [ -n "$flag" ]; then
      append_arg "$flag"
    fi
    append_arg "$entry"
  done <<EOF
$(printf '%s\n' "$items" | tr ',' '\n')
EOF
}

# Normalize host portion from IPv4/IPv6 [addr]:port formats.
extract_host_from_address() {
  address="$1"
  case "$address" in
    \[*\]:*)
      host="${address#\[}"
      host="${host%%]*}"
      printf '%s\n' "$host"
      ;;
    \[*\])
      host="${address#\[}"
      host="${host%%]*}"
      printf '%s\n' "$host"
      ;;
    *:*:*)
      printf '%s\n' "$address"
      ;;
    *:*)
      host="${address%:*}"
      printf '%s\n' "$host"
      ;;
    *)
      printf '%s\n' "$address"
      ;;
  esac
}

# Extract port portion for defaults and validation.
extract_port_from_address() {
  address="$1"
  default_port="$2"
  case "$address" in
    \[*\]:*)
      port="${address##*]:}"
      ;;
    *:*:*)
      port="$default_port"
      ;;
    *:*)
      port="${address##*:}"
      ;;
    *)
      port="$default_port"
      ;;
  esac
  if [ -z "$port" ]; then
    port="$default_port"
  fi
  printf '%s\n' "$port"
}

# Inspect effective capabilities for NET_BIND_SERVICE.
has_cap_net_bind_service() {
  cap_eff=$(awk '/CapEff/ {print $2}' /proc/self/status 2>/dev/null || true)
  if [ -z "$cap_eff" ]; then
    return 1
  fi
  cap_value=$((16#$cap_eff))
  if [ $((cap_value & (1 << 10))) -ne 0 ]; then
    return 0
  fi
  return 1
}

# Bail out early if we cannot bind to privileged ports.
ensure_privileged_port_access() {
  port="$1"
  case "$port" in
    ''|*[!0-9]*) return ;;
  esac
  if [ "$port" -ge 1024 ]; then
    return
  fi
  uid=$(id -u 2>/dev/null || echo 0)
  if [ "$uid" -eq 0 ]; then
    return
  fi
  if has_cap_net_bind_service; then
    return
  fi
  log_error "Cannot bind to privileged port ${port} without NET_BIND_SERVICE capability or root privileges."
  exit 1
}

# Confirm every requested port-range entry is permitted before starting.
validate_port_range_bindability() {
  range="$1"
  IFS=':' read -r start end <<EOF
$range
EOF
  if [ -z "$start" ] || [ -z "$end" ]; then
    return
  fi
  case "$start" in ''|*[!0-9]*) return ;; esac
  case "$end" in ''|*[!0-9]*) return ;; esac
  if [ "$start" -gt "$end" ]; then
    temp="$start"
    start="$end"
    end="$temp"
  fi
  log "Validating port range ${start}:${end}"
  port="$start"
  while [ "$port" -le "$end" ]; do
    ensure_privileged_port_access "$port"
    port=$((port + 1))
  done
}

# Derive the best-effort pod IP for address normalization.
detect_pod_ip() {
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$(hostname 2>/dev/null)" | awk '!/^127\./ {print $1; exit}'
  else
    hostname -i 2>/dev/null | tr ' ' '\n' | awk '!/^127\./ {print; exit}'
  fi
}

TFTPD_ARGS=""

# Network and process behavior flags.
CURRENT_STAGE="network configuration"
log "Configuring network flags"
append_flag_if_enabled "${TFTPD_USE_IPV4:-}" "--ipv4"
append_flag_if_enabled "${TFTPD_USE_IPV6:-}" "--ipv6"
append_flag_if_enabled "${TFTPD_LISTEN:-}" "--listen"
append_flag_if_enabled "${TFTPD_FOREGROUND:-true}" "--foreground"
TFTPD_ADDRESS_VALUE="${TFTPD_ADDRESS:-}"
POD_IP=""
if POD_INFO=$(detect_pod_ip); then
  POD_IP="$POD_INFO"
  if [ -n "$POD_IP" ]; then
    log "Detected pod IP ${POD_IP}"
  else
    log "Pod IP detection returned empty result"
  fi
else
  log "Pod IP detection failed"
fi
if [ -n "$TFTPD_ADDRESS_VALUE" ] && [ -n "$POD_IP" ] && ! is_enabled "${HOSTNETWORK:-}"; then
  address_host="$(extract_host_from_address "$TFTPD_ADDRESS_VALUE")"
  address_port="$(extract_port_from_address "$TFTPD_ADDRESS_VALUE" "69")"
  if [ -n "$address_host" ] && [ "$address_host" != "$POD_IP" ]; then
    log "TFTPD_ADDRESS host '${address_host}' does not match pod IP '${POD_IP}' and hostNetwork=false. Normalizing to ${POD_IP}:${address_port}."
    TFTPD_ADDRESS_VALUE="${POD_IP}:${address_port}"
  fi
fi
append_arg_with_value "--address" "${TFTPD_ADDRESS_VALUE}"

# File handling and security controls.
CURRENT_STAGE="file/security configuration"
log "Configuring file/security options"
append_flag_if_enabled "${TFTPD_ENABLE_CREATE:-}" "--create"
TFTPD_SECURE_MODE_VALUE="${TFTPD_SECURE_MODE:-true}"
TFTPD_SECURE_ENABLED="false"
if is_enabled "$TFTPD_SECURE_MODE_VALUE"; then
  TFTPD_SECURE_ENABLED="true"
fi
append_flag_if_enabled "${TFTPD_SECURE_MODE_VALUE}" "--secure"
append_arg_with_value "--user" "${TFTPD_USER:-}"
append_arg_with_value "--umask" "${TFTPD_UMASK:-}"
append_flag_if_enabled "${TFTPD_PERMISSIVE:-}" "--permissive"
append_arg_with_value "--pidfile" "${TFTPD_PIDFILE:-}"

# Timing and retransmission behavior.
CURRENT_STAGE="timing configuration"
log "Configuring timing parameters"
append_arg_with_value "--timeout" "${TFTPD_TIMEOUT:-}"
append_arg_with_value "--retransmit" "${TFTPD_RETRANSMIT_TIMEOUT:-}"

# Mapping and logging controls.
CURRENT_STAGE="mapping/verbosity configuration"
log "Configuring mapping and verbosity"
append_arg_with_value "--mapfile" "${TFTPD_MAPFILE:-}"

if [ -n "${TFTPD_VERBOSE_COUNT:-}" ]; then
  count="${TFTPD_VERBOSE_COUNT}"
  case "$count" in
    ''|*[!0-9]*) count=0 ;;
  esac
  while [ "$count" -gt 0 ]; do
    append_arg "--verbose"
    count=$((count - 1))
  done || true
else
  append_flag_if_enabled "${TFTPD_VERBOSE:-}" "--verbose"
fi

append_arg_with_value "--verbosity" "${TFTPD_VERBOSITY:-}"

append_list_items "--refuse" "${TFTPD_REFUSE_OPTIONS:-}"
log "Completed mapping and verbosity configuration"

# Transfer tuning.
CURRENT_STAGE="transfer configuration"
log "Configuring transfer settings"
append_arg_with_value "--blocksize" "${TFTPD_BLOCKSIZE:-}"
TFTPD_PORT_RANGE_VALUE="${TFTPD_PORT_RANGE:-}"
append_arg_with_value "--port-range" "${TFTPD_PORT_RANGE_VALUE}"
append_flag_if_enabled "${TFTPD_SHOW_VERSION:-}" "--version"

# Directory arguments (defaults to original secure root).
CURRENT_STAGE="directory validation"
TFTPD_ROOT="${TFTPD_ROOT:-/var/tftpboot}"
TFTPD_DIRECTORIES="${TFTPD_DIRECTORIES:-$TFTPD_ROOT}"
if [ "$TFTPD_SECURE_ENABLED" = "true" ]; then
  log "Secure mode enabled; validating single directory constraint"
  dir_count=0
  while IFS= read -r entry; do
    entry="$(trim_spaces "$entry")"
    if [ -z "$entry" ]; then
      continue
    fi
    dir_count=$((dir_count + 1))
  done <<EOF
$(printf '%s\n' "$TFTPD_DIRECTORIES" | tr ',' '\n')
EOF
  if [ "$dir_count" -gt 1 ]; then
    log_error "Secure mode only supports a single directory but ${dir_count} were provided (${TFTPD_DIRECTORIES}). Reduce TFTPD_DIRECTORIES to one path or disable TFTPD_SECURE_MODE."
    exit 1
  fi
fi
log "Finalizing directory access rules"
append_list_items "" "$TFTPD_DIRECTORIES"

if [ -n "$TFTPD_PORT_RANGE_VALUE" ]; then
  validate_port_range_bindability "$TFTPD_PORT_RANGE_VALUE"
fi

TFTPD_BIND_PORT="69"
if [ -n "$TFTPD_ADDRESS_VALUE" ]; then
  TFTPD_BIND_PORT="$(extract_port_from_address "$TFTPD_ADDRESS_VALUE" "69")"
fi
CURRENT_STAGE="privileged port check"
log "Ensuring access to bind port ${TFTPD_BIND_PORT}"
ensure_privileged_port_access "$TFTPD_BIND_PORT"

# Forward tftpd logs through BusyBox syslogd to stdout once env is applied.
CURRENT_STAGE="syslog initialization"
if ! pidof syslogd >/dev/null 2>&1; then
  log "Starting syslogd"
  syslogd -n -O /dev/stdout &
else
  log "syslogd already running, skipping start"
fi

# Positionally add any user-provided overrides.
CURRENT_STAGE="argument finalization"
if [ -n "$TFTPD_ARGS" ]; then
  eval "set -- $TFTPD_ARGS \"\$@\""
fi

CURRENT_STAGE="launch"
log "Launching: in.tftpd $*"
exec in.tftpd "$@"
