#!/usr/bin/env bash
set -Eeuo pipefail

BASE_STATE_DIR="/var/lib/hermes-vps"
BASE_LOG_DIR="/var/log/hermes-vps"
HERMES_GROUP="${HERMES_GROUP:-}"
HERMES_GROUP_EXPLICIT=0
HERMES_CONTAINER_NAME="${HERMES_CONTAINER_NAME:-}"
HERMES_IMAGE="${HERMES_IMAGE:-}"
HERMES_REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
STATE_DIR=""
LOG_DIR=""
BACKUP_DIR=""
HERMES_HOST_HOME=""
WORKSPACE_DIR=""
CONTAINER_BOOTSTRAP=""
HOST_SHELL=""
HERMES_CONFIG_DIR=""
HERMES_CONFIG_FILE=""
HERMES_ENV_FILE=""
HERMES_SOURCE_DIR=""
HERMES_HELPER_SUFFIX=""
HERMES_BACKUP_HELPER=""
HERMES_DOCTOR_HELPER=""
HERMES_MAINTENANCE_HELPER=""
HERMES_STATUS_HELPER=""
HERMES_LOGS_HELPER=""
HERMES_MAINTENANCE_UNIT=""
HERMES_BACKUP_UNIT=""
HERMES_CONTAINER_UID=10000
HERMES_CONTAINER_GID=10000
CONTAINER_HERMES_HOME="/opt/data"
CONTAINER_USER_HOME="${CONTAINER_HERMES_HOME}/home"
CONTAINER_WORKSPACE_DIR="/workspace"
MODEL_PROVIDER="${MODEL_PROVIDER:-}"
MODEL_BASE_URL="${MODEL_BASE_URL:-}"
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_ID="${MODEL_ID:-}"
HERMES_TIMEZONE="${HERMES_TIMEZONE:-}"
HERMES_HOST_COMMANDS="${HERMES_HOST_COMMANDS:-1}"
HERMES_GROUP_MODEL_API_KEY="${HERMES_GROUP_MODEL_API_KEY:-}"
HERMES_GROUP_TELEGRAM_BOT_TOKEN="${HERMES_GROUP_TELEGRAM_BOT_TOKEN:-}"
HERMES_GROUP_TELEGRAM_ALLOWED_USERS="${HERMES_GROUP_TELEGRAM_ALLOWED_USERS:-}"
TAILSCALE_IFACE="tailscale0"

ASSUME_YES=0
KEEP_PUBLIC_SSH=0
REQUEST_LOCKDOWN=0

resolve_group_paths() {
  local group="${HERMES_GROUP:-default}"
  [[ "$group" =~ ^[A-Za-z0-9_-]+$ ]] || fail "invalid Hermes group name: ${group}"
  HERMES_GROUP="$group"
  STATE_DIR="/var/lib/hermes-vps/groups/${group}"
  LOG_DIR="/var/log/hermes-vps/groups/${group}"
  BACKUP_DIR="${STATE_DIR}/backups"
  HERMES_HOST_HOME="${STATE_DIR}/hermes-home"
  WORKSPACE_DIR="${STATE_DIR}/workspace"
  CONTAINER_BOOTSTRAP="${STATE_DIR}/container-bootstrap.sh"
  HOST_SHELL="/var/lib/hermes-vps/shared/host-shell"
  HERMES_CONFIG_DIR="${HERMES_HOST_HOME}"
  HERMES_CONFIG_FILE="${HERMES_CONFIG_DIR}/config.yaml"
  HERMES_ENV_FILE="${HERMES_CONFIG_DIR}/.env"
  HERMES_CONTAINER_NAME="${HERMES_CONTAINER_NAME:-hermes-agent-${group}}"
  HERMES_IMAGE="${HERMES_IMAGE:-hermes-agent-${group}:managed}"
  [[ "$HERMES_CONTAINER_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "invalid Hermes container name: ${HERMES_CONTAINER_NAME}"
  [[ "$HERMES_IMAGE" =~ ^[A-Za-z0-9._:/-]+$ ]] || fail "invalid Hermes image tag: ${HERMES_IMAGE}"
  HERMES_SOURCE_DIR="${STATE_DIR}/hermes-agent-src"
  HERMES_HELPER_SUFFIX="-${group}"
  HERMES_BACKUP_HELPER="/usr/local/sbin/hermes-vps-backup${HERMES_HELPER_SUFFIX}"
  HERMES_DOCTOR_HELPER="/usr/local/sbin/hermes-vps-doctor${HERMES_HELPER_SUFFIX}"
  HERMES_MAINTENANCE_HELPER="/usr/local/sbin/hermes-vps-maintenance${HERMES_HELPER_SUFFIX}"
  HERMES_STATUS_HELPER="/usr/local/sbin/hermes-vps-status${HERMES_HELPER_SUFFIX}"
  HERMES_LOGS_HELPER="/usr/local/sbin/hermes-vps-logs${HERMES_HELPER_SUFFIX}"
  HERMES_MAINTENANCE_UNIT="hermes-vps-maintenance${HERMES_HELPER_SUFFIX}"
  HERMES_BACKUP_UNIT="hermes-vps-backup${HERMES_HELPER_SUFFIX}"
}

maybe_migrate_flat_to_group() {
  local legacy_flat_home="/var/lib/hermes-vps/hermes-home"
  local target_dir="/var/lib/hermes-vps/groups/default"
  [[ -d "$legacy_flat_home" ]] || return 0
  [[ ! -d "$target_dir" ]] || return 0

  log "migrating legacy flat Hermes state into groups/default"
  docker stop hermes-agent 2>/dev/null || true
  docker rm hermes-agent 2>/dev/null || true

  install -d -m 0700 "$target_dir"
  local item src
  if [[ -e /var/lib/hermes-vps/host-shell ]]; then
    install -d -m 0755 /var/lib/hermes-vps/shared
    mv /var/lib/hermes-vps/host-shell /var/lib/hermes-vps/shared/host-shell
  fi

  for item in hermes-home workspace container-bootstrap.sh hermes-agent-src backups; do
    src="/var/lib/hermes-vps/${item}"
    if [[ -e "$src" ]]; then
      mv "$src" "$target_dir/"
    fi
  done

  rm -f \
    /usr/local/sbin/hermes-vps-backup \
    /usr/local/sbin/hermes-vps-doctor \
    /usr/local/sbin/hermes-vps-maintenance \
    /usr/local/sbin/hermes-vps-status \
    /usr/local/sbin/hermes-vps-logs
  systemctl stop hermes-vps-maintenance.timer hermes-vps-backup.timer 2>/dev/null || true
  rm -f \
    /etc/systemd/system/hermes-vps-maintenance.service \
    /etc/systemd/system/hermes-vps-maintenance.timer \
    /etc/systemd/system/hermes-vps-backup.service \
    /etc/systemd/system/hermes-vps-backup.timer
  systemctl daemon-reload 2>/dev/null || true

  local current_group="$HERMES_GROUP"
  local current_container_name="$HERMES_CONTAINER_NAME"
  local current_image="$HERMES_IMAGE"
  HERMES_GROUP="default"
  HERMES_CONTAINER_NAME=""
  HERMES_IMAGE=""
  resolve_group_paths
  cmd_refresh_config
  HERMES_GROUP="$current_group"
  HERMES_CONTAINER_NAME="$current_container_name"
  HERMES_IMAGE="$current_image"
  resolve_group_paths
}

usage() {
  cat <<'USAGE'
Usage: ./hermes-vps.sh <command> [options]

Commands:
  install                 Harden the VPS, install Tailscale, Docker, and containerized Hermes Agent.
  add-group               Add a new Hermes container group on an already prepared VPS.
  refresh-config          Regenerate Hermes config and recreate the Hermes container with persistent volumes.
  lockdown                Enforce Tailscale-only inbound access with UFW.
  status                  Show system, Tailscale, firewall, Docker, and Hermes container status.
  backup                  Archive managed Hermes config, workspace, and container bootstrap state.
  maintenance             Run package maintenance and refresh the Hermes container image.
  logs                    Follow the Hermes container logs.
  doctor                  Run Hermes doctor and config checks inside the container.
  help                    Show this help.

Options:
  --group NAME            Hermes container group to manage. Default: default.
  --model-api-key KEY     Model provider API key for add-group; falls back to env/prompt.
  --telegram-bot-token TOKEN
                          Telegram bot token for add-group; falls back to env/prompt.
  --telegram-allow-from IDS
                          Telegram numeric user allowlist for add-group; falls back to env/prompt.
  --lockdown              After install, prompt for explicit LOCKDOWN confirmation and apply UFW lockdown.
  --keep-public-ssh       Keep public SSH open in UFW lockdown. Not recommended for final state.
  -y, --yes               Skip non-lockdown confirmations. LOCKDOWN still requires the word LOCKDOWN.

Environment overrides:
  TAILSCALE_AUTH_KEY      Optional Tailscale auth key for non-interactive tailnet join.
                          Browser login is the default when this is unset.
  MODEL_PROVIDER          Model provider identifier.
  MODEL_BASE_URL          OpenAI-compatible model API base URL.
  MODEL_API_KEY           Model provider API key.
  MODEL_ID                Default model reference.
  TELEGRAM_BOT_TOKEN      Optional Telegram bot token for Hermes gateway.
  TELEGRAM_ALLOWED_USERS  Optional comma-separated numeric Telegram user ID allowlist.
  HERMES_IMAGE            Managed local Hermes image tag. Default: hermes-agent-GROUP:managed.
  HERMES_REPO_URL         Hermes source repo used to build the managed image.
  HERMES_TIMEZONE         IANA timezone. Default: existing managed env, host timezone, then UTC.
  HERMES_HOST_COMMANDS    Set to 1 to expose host-shell inside the container for Telegram admins.

Managed appliance posture:
  - Hermes gateway runs inside a Docker container named hermes-agent-GROUP.
  - Hermes config, sessions, skills, memories, and workspace persist on the VPS host.
  - Telegram-triggered terminal commands execute inside the Hermes container.
  - Telegram admins can run VPS host commands with host-shell when HERMES_HOST_COMMANDS=1.
  - The agent container does not receive the host Docker socket or host passwordless sudo.
  - Weekly maintenance runs Sunday at 04:00 host local time and reboots afterward.

Final intended firewall posture:
  - UFW default deny incoming.
  - UFW default allow outgoing.
  - All inbound traffic allowed on tailscale0.
  - No public SSH unless --keep-public-ssh is explicitly used.
  - Hermes gateway uses outbound long polling for Telegram by default.
USAGE
}

log() {
  printf '[hermes-vps] %s\n' "$*"
}

warn() {
  printf '[hermes-vps] warning: %s\n' "$*" >&2
}

fail() {
  printf '[hermes-vps] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "$(id -u)" == "0" ]] || fail "this command must run as root"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

prompt_secret() {
  local var_name="$1"
  local prompt="$2"
  local required="$3"
  local current="${!var_name:-}"
  if [[ -n "$current" ]]; then
    printf '%s' "$current"
    return 0
  fi
  local value=""
  if [[ "$required" == "required" ]]; then
    while [[ -z "$value" ]]; do
      read -r -s -p "${prompt}: " value
      printf '\n' >&2
    done
  else
    read -r -s -p "${prompt} (leave empty to skip): " value
    printf '\n' >&2
  fi
  printf '%s' "$value"
}

shell_quote() {
  printf '%q' "$1"
}

resolve_hermes_timezone() {
  if [[ -n "$HERMES_TIMEZONE" ]]; then
    return 0
  fi
  local persisted_timezone=""
  if [[ -r "$HERMES_ENV_FILE" ]]; then
    persisted_timezone="$(bash -c 'set -a; . "$1"; set +a; printf "%s" "${HERMES_TIMEZONE:-${TZ:-}}"' bash "$HERMES_ENV_FILE")"
  fi
  if [[ -n "$persisted_timezone" ]]; then
    HERMES_TIMEZONE="$persisted_timezone"
    return 0
  fi
  if command -v timedatectl >/dev/null 2>&1; then
    HERMES_TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  fi
  HERMES_TIMEZONE="${HERMES_TIMEZONE:-UTC}"
}

preflight() {
  require_root
  [[ -r /etc/os-release ]] || fail "/etc/os-release not found"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || fail "Ubuntu is required; found ${ID:-unknown}"
  need_command systemctl
  [[ -d /run/systemd/system ]] || fail "systemd is required"

  local mem_kb disk_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  disk_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  if (( mem_kb < 1900000 )); then
    warn "less than 2 GB RAM detected; 4 GB+ is recommended"
  fi
  if (( disk_kb < 15000000 )); then
    warn "less than 15 GB free disk detected; 50 GB+ is recommended"
  fi
}

apt_install_baseline() {
  log "installing baseline hardening, Docker, and appliance support packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    docker-buildx \
    docker.io \
    fail2ban \
    git \
    jq \
    libffi-dev \
    openssh-server \
    python3 \
    python3-dev \
    ripgrep \
    sudo \
    tar \
    util-linux \
    ufw \
    unattended-upgrades
}

restart_ssh_service() {
  if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    systemctl restart ssh.service
  elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
    systemctl restart sshd.service
  else
    warn "SSH service unit not found; skipping SSH restart"
  fi
}

ensure_sshd_runtime_dir() {
  install -d -m 0755 /run/sshd
  install -d -m 0755 /var/run/sshd
}

validate_ssh_config() {
  ensure_sshd_runtime_dir
  if /usr/sbin/sshd -t; then
    return 0
  fi
  warn "sshd config validation failed once; recreating runtime directory and retrying"
  ensure_sshd_runtime_dir
  /usr/sbin/sshd -t
}

configure_ssh_hardening() {
  log "hardening SSH before credential prompts"
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-hermes-vps.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
EOF
  validate_ssh_config || fail "sshd config validation failed after hardening changes"
  restart_ssh_service
}

configure_fail2ban() {
  log "enabling fail2ban before credential prompts"
  install -d -m 0755 /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/hermes-vps-sshd.conf <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban.service
}

configure_unattended_upgrades() {
  log "enabling unattended security upgrades"
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  systemctl enable --now unattended-upgrades.service >/dev/null 2>&1 || true
}

configure_host_timezone() {
  resolve_hermes_timezone
  log "configuring host timezone: ${HERMES_TIMEZONE}"
  timedatectl set-timezone "$HERMES_TIMEZONE"
}

install_docker() {
  log "enabling Docker service"
  systemctl enable --now docker.service
  docker info >/dev/null || fail "Docker daemon is not responding"
  docker buildx version >/dev/null || fail "Docker Buildx plugin is not available"
}

install_tailscale() {
  log "installing Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh
    sh /tmp/tailscale-install.sh
    rm -f /tmp/tailscale-install.sh
  fi
  systemctl enable --now tailscaled.service
}

tailscale_up() {
  local auth_key="$1"
  log "joining Tailscale tailnet"
  if tailscale status >/dev/null 2>&1 && [[ -n "$(tailscale ip -4 2>/dev/null || true)" ]]; then
    log "Tailscale is already connected"
    return 0
  fi
  if [[ -n "$auth_key" ]]; then
    tailscale up --auth-key "$auth_key" --accept-dns=true
  else
    log "TAILSCALE_AUTH_KEY is unset; using browser login. Open the Tailscale URL printed below."
    tailscale up --accept-dns=true
  fi
  local ts_ip
  ts_ip="$(tailscale ip -4 2>/dev/null || true)"
  [[ -n "$ts_ip" ]] || fail "Tailscale did not report an IPv4 address after tailscale up"
  log "Tailscale connected at ${ts_ip}"
}

ensure_state_dirs() {
  log "ensuring persistent Hermes appliance directories"
  install -d -m 0700 "$STATE_DIR" "$HERMES_HOST_HOME"
  install -d -m 0750 "$WORKSPACE_DIR" "$BACKUP_DIR"
  install -d -m 0755 "$LOG_DIR" "$(dirname "$HOST_SHELL")"
  chown "${HERMES_CONTAINER_UID}:${HERMES_CONTAINER_GID}" "$WORKSPACE_DIR"
  chmod 0750 "$WORKSPACE_DIR"
}

write_container_bootstrap() {
  log "writing container bootstrap for reset-safe essentials"
  cat >"$CONTAINER_BOOTSTRAP" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    ripgrep \
    sudo \
    tar \
    util-linux \
    unzip
  apt-get clean
  rm -rf /var/lib/apt/lists/*
fi

mkdir -p /workspace /root/.hermes

if [[ "${HERMES_HOST_COMMANDS:-0}" == "1" ]]; then
  printf 'hermes ALL=(root) NOPASSWD: /usr/local/bin/host-shell *\n' >/etc/sudoers.d/hermes-host-shell
  chmod 0440 /etc/sudoers.d/hermes-host-shell
fi
EOF
  chmod 0755 "$CONTAINER_BOOTSTRAP"
}

write_host_shell_bridge() {
  log "writing host-shell bridge for Telegram-admin VPS commands"
  cat >"$HOST_SHELL" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -eq 0 ]]; then
  cat <<'USAGE' >&2
Usage: host-shell <command> [args...]
       host-shell -- <command string>

Runs a command in the VPS host namespaces. This bridge is intentionally
privileged and is intended for allowlisted Telegram admins only.
USAGE
  exit 64
fi

if [[ "${1:-}" == "--" ]]; then
  shift
  [[ "$#" -gt 0 ]] || exit 64
  exec nsenter --target 1 --mount --uts --ipc --net --pid --wd=/ -- bash -lc "$*"
fi

exec nsenter --target 1 --mount --uts --ipc --net --pid --wd=/ -- "$@"
EOF
  chmod 0755 "$HOST_SHELL"
}

write_user_env() {
  resolve_hermes_timezone
  local model_provider="$1" model_base_url="$2" model_api_key="$3" model_id="$4"
  local telegram_token="$5" telegram_allowed_users="$6"
  log "writing Hermes secret environment file"
  install -d -m 0700 "$HERMES_CONFIG_DIR"
  {
    printf 'MODEL_PROVIDER=%s\n' "$(shell_quote "$model_provider")"
    printf 'MODEL_BASE_URL=%s\n' "$(shell_quote "$model_base_url")"
    printf 'MODEL_API_KEY=%s\n' "$(shell_quote "$model_api_key")"
    printf 'MODEL_ID=%s\n' "$(shell_quote "$model_id")"
    printf 'HERMES_HOME=%s\n' "$(shell_quote "$CONTAINER_HERMES_HOME")"
    printf 'HERMES_TIMEZONE=%s\n' "$(shell_quote "$HERMES_TIMEZONE")"
    printf 'TZ=%s\n' "$(shell_quote "$HERMES_TIMEZONE")"
    printf 'TERMINAL_CWD=%s\n' "$(shell_quote "$CONTAINER_WORKSPACE_DIR")"
    printf 'TERMINAL_ENV=local\n'
    printf 'PYTHONUNBUFFERED=1\n'
    if [[ -n "$telegram_token" ]]; then
      printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(shell_quote "$telegram_token")"
    fi
    if [[ -n "$telegram_allowed_users" ]]; then
      printf 'TELEGRAM_ALLOWED_USERS=%s\n' "$(shell_quote "$telegram_allowed_users")"
    fi
  } >"$HERMES_ENV_FILE"
  chown "${HERMES_CONTAINER_UID}:${HERMES_CONTAINER_GID}" "$HERMES_ENV_FILE"
  chmod 0640 "$HERMES_ENV_FILE"
}

prune_deprecated_env() {
  [[ -f "$HERMES_ENV_FILE" ]] || return 0
  local tmp_file
  tmp_file="$(mktemp)"
  awk '$0 !~ /^MESSAGING_CWD=/' "$HERMES_ENV_FILE" >"$tmp_file"
  install -m 0600 "$tmp_file" "$HERMES_ENV_FILE"
  rm -f "$tmp_file"
}

refresh_user_env() {
  [[ -f "$HERMES_ENV_FILE" ]] || fail "Hermes env file missing: ${HERMES_ENV_FILE}"
  local existing_model_api_key existing_token existing_allowed value
  local -a values=()
  while IFS= read -r value; do
    values+=("$value")
  done < <(bash -c 'set -a; . "$1"; set +a; printf "%s\n%s\n%s\n" "${MODEL_API_KEY:-}" "${TELEGRAM_BOT_TOKEN:-}" "${TELEGRAM_ALLOWED_USERS:-}"' bash "$HERMES_ENV_FILE")
  existing_model_api_key="${MODEL_API_KEY:-${values[0]:-}}"
  existing_token="${TELEGRAM_BOT_TOKEN:-${values[1]:-}}"
  existing_allowed="${TELEGRAM_ALLOWED_USERS:-${values[2]:-}}"
  [[ -n "$existing_model_api_key" ]] || fail "Hermes env file is missing a model provider API key"
  write_user_env "$MODEL_PROVIDER" "$MODEL_BASE_URL" "$existing_model_api_key" "$MODEL_ID" "$existing_token" "$existing_allowed"
}

write_yaml_list() {
  local indent="$1"
  local csv="$2"
  local item trimmed
  IFS=',' read -ra items <<<"$csv"
  for item in "${items[@]}"; do
    trimmed="${item#${item%%[![:space:]]*}}"
    trimmed="${trimmed%${trimmed##*[![:space:]]}}"
    [[ -n "$trimmed" ]] || continue
    printf '%s- "%s"\n' "$indent" "$trimmed"
  done
}

write_hermes_config() {
  resolve_hermes_timezone
  local telegram_allowed_users="${TELEGRAM_ALLOWED_USERS:-}"
  if [[ -r "$HERMES_ENV_FILE" && -z "$telegram_allowed_users" ]]; then
    telegram_allowed_users="$(bash -c 'set -a; . "$1"; set +a; printf "%s" "${TELEGRAM_ALLOWED_USERS:-}"' bash "$HERMES_ENV_FILE")"
  fi
  log "writing Hermes config for ${MODEL_PROVIDER:-configured provider} ${MODEL_ID}"
  install -d -m 0700 "$HERMES_CONFIG_DIR"
  {
    printf 'model:\n'
    printf '  provider: %s\n' "$MODEL_PROVIDER"
    printf '  default: %s\n' "$MODEL_ID"
    printf 'providers:\n'
    printf '  %s:\n' "$MODEL_PROVIDER"
    printf '    base_url: %s\n' "$MODEL_BASE_URL"
    printf '    api_key: ${MODEL_API_KEY}\n'
    printf 'terminal:\n'
    printf '  backend: local\n'
    printf '  cwd: %s\n' "$CONTAINER_WORKSPACE_DIR"
    printf '  timeout: 180\n'
    printf 'approvals:\n'
    printf '  mode: manual\n'
    printf '  timeout: 60\n'
    printf 'telegram:\n'
    printf '  require_mention: true\n'
    printf 'gateway:\n'
    printf '  streaming:\n'
    printf '    enabled: true\n'
    printf '    transport: auto\n'
    printf '  platforms:\n'
    printf '    telegram:\n'
    printf '      enabled: true\n'
    printf '      extra:\n'
    printf '        require_mention: true\n'
    if [[ -n "$telegram_allowed_users" ]]; then
      printf '        allow_from:\n'
      write_yaml_list '          ' "$telegram_allowed_users"
      printf '        allow_admin_from:\n'
      write_yaml_list '          ' "$telegram_allowed_users"
    else
      printf '        allow_from: []\n'
      printf '        allow_admin_from: []\n'
    fi
    printf '        user_allowed_commands:\n'
    printf '          - status\n'
    printf '          - model\n'
    printf '          - help\n'
    printf 'display:\n'
    printf '  tool_progress: all\n'
    printf '  background_process_notifications: all\n'
  } >"$HERMES_CONFIG_FILE"
  chown "${HERMES_CONTAINER_UID}:${HERMES_CONTAINER_GID}" "$HERMES_CONFIG_FILE"
  chmod 0640 "$HERMES_CONFIG_FILE"
}

sync_hermes_source() {
  if [[ -d "${HERMES_SOURCE_DIR}/.git" ]]; then
    log "updating Hermes source checkout"
    git -C "$HERMES_SOURCE_DIR" fetch --depth 1 origin
    git -C "$HERMES_SOURCE_DIR" reset --hard origin/main
  else
    log "cloning Hermes source checkout"
    rm -rf "$HERMES_SOURCE_DIR"
    git clone --depth 1 "$HERMES_REPO_URL" "$HERMES_SOURCE_DIR"
  fi
}

build_hermes_image() {
  sync_hermes_source
  log "building Hermes container image: ${HERMES_IMAGE}"
  DOCKER_BUILDKIT=1 docker build --pull -t "$HERMES_IMAGE" "$HERMES_SOURCE_DIR"
}

start_hermes_container() {
  ensure_state_dirs
  [[ -r "$HERMES_ENV_FILE" ]] || fail "Hermes env file missing: ${HERMES_ENV_FILE}"
  [[ -r "$HERMES_CONFIG_FILE" ]] || fail "Hermes config file missing: ${HERMES_CONFIG_FILE}"
  [[ -x "$CONTAINER_BOOTSTRAP" ]] || write_container_bootstrap
  if [[ "$HERMES_HOST_COMMANDS" == "1" ]]; then
    [[ -x "$HOST_SHELL" ]] || write_host_shell_bridge
  fi
  build_hermes_image
  log "starting Hermes container: ${HERMES_CONTAINER_NAME}"
  docker rm -f "$HERMES_CONTAINER_NAME" >/dev/null 2>&1 || true
  local host_command_args=()
  if [[ "$HERMES_HOST_COMMANDS" == "1" ]]; then
    host_command_args=(
      --privileged
      --pid host
      -v "${HOST_SHELL}:/usr/local/bin/host-shell:ro"
    )
  fi
  docker run -d \
    --name "$HERMES_CONTAINER_NAME" \
    --restart unless-stopped \
    "${host_command_args[@]}" \
    --env-file "$HERMES_ENV_FILE" \
    -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" \
    -e "HOME=${CONTAINER_USER_HOME}" \
    -e "HERMES_HOST_COMMANDS=${HERMES_HOST_COMMANDS}" \
    -e "TZ=${HERMES_TIMEZONE}" \
    -e "TERMINAL_ENV=local" \
    -v "${HERMES_HOST_HOME}:${CONTAINER_HERMES_HOME}" \
    -v "${WORKSPACE_DIR}:${CONTAINER_WORKSPACE_DIR}" \
    -v "${CONTAINER_BOOTSTRAP}:/usr/local/bin/hermes-container-bootstrap:ro" \
    --entrypoint /bin/bash \
    "$HERMES_IMAGE" \
    -lc 'hermes-container-bootstrap && cd /workspace && exec /opt/hermes/docker/entrypoint.sh gateway run --replace' >/dev/null
  wait_for_hermes_container
}

wait_for_hermes_container() {
  local attempt running
  for attempt in {1..60}; do
    running="$(docker inspect -f '{{.State.Running}}' "$HERMES_CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$running" == "true" ]] && docker exec -u hermes -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" -e "HOME=${CONTAINER_USER_HOME}" "$HERMES_CONTAINER_NAME" /opt/hermes/.venv/bin/hermes --version >/dev/null 2>&1; then
      log "Hermes container is running"
      return 0
    fi
    sleep 2
  done
  docker logs --tail 120 "$HERMES_CONTAINER_NAME" >&2 || true
  fail "Hermes container did not become healthy"
}

write_helper_scripts() {
  log "writing maintenance, backup, status, doctor, and log helper scripts"
  cat >"$HERMES_BACKUP_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR="${STATE_DIR}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_DIR="${LOG_DIR}"
mkdir -p "\$BACKUP_DIR" "\$LOG_DIR"
archive="\$BACKUP_DIR/hermes-vps-\$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
tar -czf "\$archive" -C "\$STATE_DIR" hermes-home workspace container-bootstrap.sh
find "\$BACKUP_DIR" -type f -name 'hermes-vps-*.tar.gz' -mtime +30 -delete
printf 'backup written: %s\n' "\$archive"
EOF
  chmod 0755 "$HERMES_BACKUP_HELPER"

  cat >"$HERMES_DOCTOR_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
HERMES_CONTAINER_NAME="${HERMES_CONTAINER_NAME}"
docker exec -u hermes -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" -e "HOME=${CONTAINER_USER_HOME}" "\$HERMES_CONTAINER_NAME" /opt/hermes/.venv/bin/hermes doctor || true
docker exec -u hermes -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" -e "HOME=${CONTAINER_USER_HOME}" "\$HERMES_CONTAINER_NAME" /opt/hermes/.venv/bin/hermes config check || true
EOF
  chmod 0755 "$HERMES_DOCTOR_HELPER"

  cat >"$HERMES_MAINTENANCE_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
HERMES_GROUP="${HERMES_GROUP}"
LOG_DIR="${LOG_DIR}"
SCRIPT_PATH="/root/hermes-vps.sh"
mkdir -p "\$LOG_DIR"
log_file="\$LOG_DIR/maintenance-\$(date -u +%Y%m%dT%H%M%SZ).log"
REBOOT=0
if [[ "\${1:-}" == "--reboot" ]]; then
  REBOOT=1
fi
{
  echo "maintenance started \$(date -u --iso-8601=seconds)"
  if [[ "\$HERMES_GROUP" == "default" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get -y upgrade
    apt-get -y autoremove
    apt-get -y autoclean
    systemctl enable --now docker.service
  fi
  ${HERMES_BACKUP_HELPER} || true
  "\$SCRIPT_PATH" --group "\$HERMES_GROUP" refresh-config
  if [[ "\$HERMES_GROUP" == "default" ]]; then
    docker image prune -af --filter "until=168h" || true
  fi
  ${HERMES_DOCTOR_HELPER} || true
  echo "maintenance finished \$(date -u --iso-8601=seconds)"
  if [[ "\$HERMES_GROUP" == "default" && "\$REBOOT" == "1" ]]; then
    echo "weekly managed reboot requested"
    systemctl reboot
  fi
} 2>&1 | tee -a "\$log_file"
EOF
  chmod 0755 "$HERMES_MAINTENANCE_HELPER"

  cat >"$HERMES_STATUS_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
HERMES_CONTAINER_NAME="${HERMES_CONTAINER_NAME}"
echo "== system =="
hostnamectl || true
echo
echo "== tailscale =="
tailscale status || true
echo
echo "== firewall =="
ufw status verbose || true
echo
echo "== docker =="
docker ps --filter "name=^/\$HERMES_CONTAINER_NAME$" || true
docker inspect --format 'status={{.State.Status}} restart={{.HostConfig.RestartPolicy.Name}} image={{.Config.Image}}' "\$HERMES_CONTAINER_NAME" 2>/dev/null || true
echo
echo "== hermes =="
docker exec -u hermes -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" -e "HOME=${CONTAINER_USER_HOME}" "\$HERMES_CONTAINER_NAME" /opt/hermes/.venv/bin/hermes --version || true
docker exec -u hermes -e "HERMES_HOME=${CONTAINER_HERMES_HOME}" -e "HOME=${CONTAINER_USER_HOME}" "\$HERMES_CONTAINER_NAME" /opt/hermes/.venv/bin/hermes config check || true
echo
echo "== recent logs =="
docker logs --tail 80 "\$HERMES_CONTAINER_NAME" || true
EOF
  chmod 0755 "$HERMES_STATUS_HELPER"

  cat >"$HERMES_LOGS_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
HERMES_CONTAINER_NAME="${HERMES_CONTAINER_NAME}"
exec docker logs -f "\$HERMES_CONTAINER_NAME"
EOF
  chmod 0755 "$HERMES_LOGS_HELPER"
}

write_systemd_timers() {
  log "writing systemd maintenance and backup timers"
  local maintenance_exec="${HERMES_MAINTENANCE_HELPER}"
  if [[ "$HERMES_GROUP" == "default" ]]; then
    maintenance_exec="${HERMES_MAINTENANCE_HELPER} --reboot"
  fi
  cat >"/etc/systemd/system/${HERMES_MAINTENANCE_UNIT}.service" <<EOF
[Unit]
Description=Hermes VPS weekly maintenance (${HERMES_GROUP})
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=${maintenance_exec}
EOF

  cat >"/etc/systemd/system/${HERMES_MAINTENANCE_UNIT}.timer" <<EOF
[Unit]
Description=Run Hermes VPS maintenance weekly (${HERMES_GROUP})

[Timer]
OnCalendar=Sun 04:00
AccuracySec=1min
Persistent=true
RandomizedDelaySec=20m

[Install]
WantedBy=timers.target
EOF

  cat >"/etc/systemd/system/${HERMES_BACKUP_UNIT}.service" <<EOF
[Unit]
Description=Hermes VPS daily backup (${HERMES_GROUP})

[Service]
Type=oneshot
ExecStart=${HERMES_BACKUP_HELPER}
EOF

  cat >"/etc/systemd/system/${HERMES_BACKUP_UNIT}.timer" <<EOF
[Unit]
Description=Run Hermes VPS backup daily (${HERMES_GROUP})

[Timer]
OnCalendar=*-*-* 03:15
Persistent=true
RandomizedDelaySec=20m

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${HERMES_MAINTENANCE_UNIT}.timer" "${HERMES_BACKUP_UNIT}.timer"
}

ensure_tailscale_connected() {
  command -v tailscale >/dev/null 2>&1 || fail "tailscale is not installed"
  systemctl is-active --quiet tailscaled.service || fail "tailscaled is not active"
  local ts_ip
  ts_ip="$(tailscale ip -4 2>/dev/null || true)"
  [[ -n "$ts_ip" ]] || fail "Tailscale has no IPv4 address; refusing to lock down public access"
  ip link show "$TAILSCALE_IFACE" >/dev/null 2>&1 || fail "${TAILSCALE_IFACE} interface not found"
}

lockdown_firewall() {
  require_root
  ensure_tailscale_connected
  if [[ "$KEEP_PUBLIC_SSH" != "1" ]]; then
    local confirmation=""
    printf '\nThis will block public inbound SSH and allow inbound access only through %s.\n' "$TAILSCALE_IFACE"
    printf 'Keep a provider console open in case your tailnet session is not working.\n'
    read -r -p 'Type LOCKDOWN to continue: ' confirmation
    [[ "$confirmation" == "LOCKDOWN" ]] || fail "lockdown cancelled"
  fi

  log "applying UFW Tailscale-only firewall policy"
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow in on "$TAILSCALE_IFACE"
  ufw allow out on "$TAILSCALE_IFACE"
  if [[ "$KEEP_PUBLIC_SSH" == "1" ]]; then
    warn "keeping public SSH open because --keep-public-ssh was provided"
    ufw allow OpenSSH
  fi
  ufw --force enable
  ufw status verbose
}

install_all() {
  [[ "$HERMES_GROUP" == "default" ]] || fail "install always manages the default group; use add-group for named groups"
  preflight
  maybe_migrate_flat_to_group
  apt_install_baseline
  configure_ssh_hardening
  configure_fail2ban
  configure_unattended_upgrades
  configure_host_timezone
  install_docker

  log "baseline hardening is active; prompting for setup credentials"
  local tailscale_auth_key model_api_key telegram_bot_token telegram_allowed_users
  tailscale_auth_key="${TAILSCALE_AUTH_KEY:-}"
  model_api_key="$(prompt_secret MODEL_API_KEY 'Model provider API key' required)"
  telegram_bot_token="$(prompt_secret TELEGRAM_BOT_TOKEN 'Telegram bot token' optional)"
  telegram_allowed_users="${TELEGRAM_ALLOWED_USERS:-}"
  if [[ -n "$telegram_bot_token" && -z "$telegram_allowed_users" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist (leave empty for pairing flow): ' telegram_allowed_users
  fi

  ensure_state_dirs
  install_tailscale
  tailscale_up "$tailscale_auth_key"
  write_container_bootstrap
  write_host_shell_bridge
  write_user_env "$MODEL_PROVIDER" "$MODEL_BASE_URL" "$model_api_key" "$MODEL_ID" "$telegram_bot_token" "$telegram_allowed_users"
  write_hermes_config
  start_hermes_container
  write_helper_scripts
  write_systemd_timers

  log "install complete"
  log "run './hermes-vps.sh status' to inspect the system"
  if [[ -n "$telegram_bot_token" && -z "$telegram_allowed_users" ]]; then
    log "Telegram pairing flow: exec into the container and approve the pairing code after DMing the bot."
    log "Example: docker exec -it ${HERMES_CONTAINER_NAME} hermes pairing list"
  fi

  if [[ "$REQUEST_LOCKDOWN" == "1" ]]; then
    lockdown_firewall
  else
    warn "public firewall lockdown was not applied. Run './hermes-vps.sh lockdown' after confirming Tailscale access."
  fi
}

group_env_value() {
  local suffix="$1"
  local fallback="$2"
  local group_env_name
  group_env_name="$(printf '%s' "$HERMES_GROUP" | tr '[:lower:]' '[:upper:]')"
  group_env_name="${group_env_name//-/_}"
  local var_name="HERMES_GROUP_${group_env_name}_${suffix}"
  if [[ "$suffix" == "MODEL_API_KEY" ]]; then
    var_name="HERMES_GROUP_${group_env_name}_MODEL_API_KEY"
  fi
  printf '%s' "${!var_name:-$fallback}"
}

prompt_group_secret() {
  local label="$1"
  local required="$2"
  local value=""
  if [[ "$required" == "required" ]]; then
    while [[ -z "$value" ]]; do
      read -r -s -p "${label}: " value
      printf '\n' >&2
    done
  else
    read -r -s -p "${label} (leave empty to skip): " value
    printf '\n' >&2
  fi
  printf '%s' "$value"
}

cmd_add_group() {
  require_root
  [[ "$HERMES_GROUP_EXPLICIT" == "1" ]] || fail "add-group requires --group NAME"
  [[ "$HERMES_GROUP" != "default" ]] || fail "add-group requires a non-default group name"

  install_docker
  ensure_state_dirs

  local model_api_key telegram_bot_token telegram_allowed_users
  model_api_key="$(group_env_value MODEL_API_KEY "$HERMES_GROUP_MODEL_API_KEY")"
  telegram_bot_token="$(group_env_value TELEGRAM_BOT_TOKEN "$HERMES_GROUP_TELEGRAM_BOT_TOKEN")"
  telegram_allowed_users="$(group_env_value TELEGRAM_ALLOWED_USERS "$HERMES_GROUP_TELEGRAM_ALLOWED_USERS")"

  if [[ -z "$model_api_key" ]]; then
    model_api_key="$(prompt_group_secret 'Model provider API key for this Hermes group' required)"
  fi
  if [[ -z "$telegram_bot_token" ]]; then
    telegram_bot_token="$(prompt_group_secret 'Telegram bot token for this Hermes group' optional)"
  fi
  if [[ -n "$telegram_bot_token" && -z "$telegram_allowed_users" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist for this Hermes group (leave empty for pairing flow): ' telegram_allowed_users
  fi

  write_container_bootstrap
  write_host_shell_bridge
  write_user_env "$MODEL_PROVIDER" "$MODEL_BASE_URL" "$model_api_key" "$MODEL_ID" "$telegram_bot_token" "$telegram_allowed_users"
  write_hermes_config
  start_hermes_container
  write_helper_scripts
  write_systemd_timers

  log "Hermes group ${HERMES_GROUP} added"
  local ts_ip
  ts_ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  if [[ -n "$ts_ip" ]]; then
    printf '\nHermes group setup finished.\n'
    printf '  Group:       %s\n' "$HERMES_GROUP"
    printf '  Tailscale IP:%s\n' " ${ts_ip}"
    printf '\nNo new root password was generated for this group. Use the VPS root password printed during the original server install, your SSH key, or provider console recovery.\n'
    printf '\nSSH via Tailscale:\n'
    printf '  ssh root@%s\n' "$ts_ip"
    printf '\nGroup commands:\n'
    printf '  ssh root@%s /root/hermes-vps.sh --group %s status\n' "$ts_ip" "$HERMES_GROUP"
    printf '  ssh root@%s /root/hermes-vps.sh --group %s doctor\n' "$ts_ip" "$HERMES_GROUP"
    printf '  ssh root@%s /root/hermes-vps.sh --group %s logs\n' "$ts_ip" "$HERMES_GROUP"
  fi
}

cmd_status() {
  require_root
  if [[ -x "$HERMES_STATUS_HELPER" ]]; then
    "$HERMES_STATUS_HELPER"
  else
    warn "helper not installed yet; showing minimal status"
    systemctl status fail2ban --no-pager || true
    tailscale status || true
    ufw status verbose || true
    docker ps || true
  fi
}

cmd_refresh_config() {
  require_root
  if [[ "$HERMES_GROUP" == "default" ]]; then
    maybe_migrate_flat_to_group
  fi
  install_docker
  ensure_state_dirs
  resolve_hermes_timezone
  prune_deprecated_env
  refresh_user_env
  write_container_bootstrap
  write_host_shell_bridge
  write_hermes_config
  start_hermes_container
  write_helper_scripts
  write_systemd_timers
  log "Hermes container config refreshed"
}

cmd_backup() {
  require_root
  [[ -x "$HERMES_BACKUP_HELPER" ]] || fail "backup helper not installed for group ${HERMES_GROUP}; run install or add-group first"
  "$HERMES_BACKUP_HELPER"
}

cmd_maintenance() {
  require_root
  [[ -x "$HERMES_MAINTENANCE_HELPER" ]] || fail "maintenance helper not installed for group ${HERMES_GROUP}; run install or add-group first"
  "$HERMES_MAINTENANCE_HELPER"
}

cmd_logs() {
  require_root
  [[ -x "$HERMES_LOGS_HELPER" ]] || fail "logs helper not installed for group ${HERMES_GROUP}; run install or add-group first"
  "$HERMES_LOGS_HELPER"
}

cmd_doctor() {
  require_root
  [[ -x "$HERMES_DOCTOR_HELPER" ]] || fail "doctor helper not installed for group ${HERMES_GROUP}; run install or add-group first"
  "$HERMES_DOCTOR_HELPER"
}

parse_options() {
  while (($#)); do
    case "$1" in
      --group)
        [[ -n "${2:-}" ]] || fail "--group requires a value"
        HERMES_GROUP="$2"
        HERMES_GROUP_EXPLICIT=1
        resolve_group_paths
        shift 2
        ;;
      --model-api-key)
        [[ -n "${2:-}" ]] || fail "--model-api-key requires a value"
        HERMES_GROUP_MODEL_API_KEY="$2"
        shift 2
        ;;
      --telegram-bot-token)
        [[ -n "${2:-}" ]] || fail "--telegram-bot-token requires a value"
        HERMES_GROUP_TELEGRAM_BOT_TOKEN="$2"
        shift 2
        ;;
      --telegram-allow-from)
        [[ -n "${2:-}" ]] || fail "--telegram-allow-from requires a value"
        HERMES_GROUP_TELEGRAM_ALLOWED_USERS="$2"
        shift 2
        ;;
      --lockdown)
        REQUEST_LOCKDOWN=1
        shift
        ;;
      --keep-public-ssh)
        KEEP_PUBLIC_SSH=1
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done
}

main() {
  local args=()
  while (($#)); do
    case "$1" in
      --group)
        [[ -n "${2:-}" ]] || fail "--group requires a value"
        HERMES_GROUP="$2"
        HERMES_GROUP_EXPLICIT=1
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  set -- "${args[@]}"
  resolve_group_paths
  local command="${1:-help}"
  if (($#)); then
    shift
  fi
  case "$command" in
    install)
      parse_options "$@"
      install_all
      ;;
    add-group)
      parse_options "$@"
      cmd_add_group
      ;;
    refresh-config)
      cmd_refresh_config
      ;;
    lockdown)
      parse_options "$@"
      lockdown_firewall
      ;;
    status)
      cmd_status
      ;;
    backup)
      cmd_backup
      ;;
    maintenance)
      cmd_maintenance
      ;;
    logs)
      cmd_logs
      ;;
    doctor)
      cmd_doctor
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage >&2
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
