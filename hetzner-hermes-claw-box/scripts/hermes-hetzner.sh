#!/usr/bin/env bash
set -Eeuo pipefail

HETZNER_LOCATION="${HETZNER_LOCATION:-fsn1}"
HETZNER_SERVER_TYPE="${HETZNER_SERVER_TYPE:-cx23}"
HETZNER_IMAGE="${HETZNER_IMAGE:-ubuntu-24.04}"
HETZNER_SERVER_NAME="${HETZNER_SERVER_NAME:-hermes-$(date +%Y%m%d-%H%M%S)}"
HETZNER_API_BASE="https://api.hetzner.cloud/v1"
HERMES_VPS_URL="${HERMES_VPS_URL:-https://raw.githubusercontent.com/ceckenrode/agent-box/main/hermes-vps.sh}"
HERMES_TIMEZONE="${HERMES_TIMEZONE:-}"
HERMES_TERMINAL_BACKEND="${HERMES_TERMINAL_BACKEND:-local}"
HERMES_SUDO_NOPASSWD="${HERMES_SUDO_NOPASSWD:-0}"
HERMES_GROUP="${HERMES_GROUP:-}"
HERMES_GROUP_MODEL_API_KEY="${HERMES_GROUP_MODEL_API_KEY:-}"
HERMES_GROUP_TELEGRAM_BOT_TOKEN="${HERMES_GROUP_TELEGRAM_BOT_TOKEN:-}"
HERMES_GROUP_TELEGRAM_ALLOWED_USERS="${HERMES_GROUP_TELEGRAM_ALLOWED_USERS:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMAND="install"
ASSUME_YES=0
KEEP_PUBLIC_SSH=0
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-}"
SSH_PRIVATE_KEY_PATH=""
CREDENTIALS_FILE="${CREDENTIALS_FILE:-}"
REMOTE_HOST=""
HETZNER_API_TOKEN="${HETZNER_API_TOKEN:-}"
MODEL_PROVIDER="${MODEL_PROVIDER:-}"
MODEL_BASE_URL="${MODEL_BASE_URL:-}"
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_ID="${MODEL_ID:-}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"
HERMES_SSH_KEY_PASSPHRASE="${HERMES_SSH_KEY_PASSPHRASE:-}"
CREATED_SERVER_ID=""
CREATED_SERVER_IP=""
CREATED_SERVER_TAILSCALE_IP=""
ROOT_PASSWORD=""
TEMP_SSH_AGENT_STARTED=0

usage() {
  cat <<'USAGE'
Usage: ./hermes-hetzner.sh [command] [options]

Create a new Hetzner Cloud server from your computer and install Hermes Agent on it.

Commands:
  install                Create a new Hetzner Cloud server and install Hermes Agent. Default.
  preflight              Validate tools, credentials, and server capacity before install.
  add-group              Add a Hermes container group on an existing Hermes VPS.
  status                 Run /root/hermes-vps.sh status on an existing Hermes VPS.
  doctor                 Run /root/hermes-vps.sh doctor on an existing Hermes VPS.
  refresh-config         Run /root/hermes-vps.sh refresh-config on an existing Hermes VPS.
  backup                 Run /root/hermes-vps.sh backup on an existing Hermes VPS.
  maintenance            Run /root/hermes-vps.sh maintenance on an existing Hermes VPS.
  logs                   Follow /root/hermes-vps.sh logs on an existing Hermes VPS.

Defaults:
  - location: fsn1 (Falkenstein)
  - server type: cx23 (cheap shared x86)
  - image: ubuntu-24.04
  - Tailscale: browser login during remote install

Options:
  --server-name NAME     Override generated server name.
  --host HOST            Existing VPS Tailscale IP or hostname for lifecycle commands.
  --group NAME           Hermes container group for existing-host lifecycle commands.
  --model-api-key KEY    Model provider API key to pass to add-group.
  --telegram-bot-token TOKEN
                         Telegram bot token to pass to add-group.
  --telegram-allow-from IDS
                         Telegram numeric user allowlist to pass to add-group.
  --ssh-key PATH         SSH public key to upload, e.g. ~/.ssh/id_ed25519.pub.
  --credentials-file PATH
                         Save the one-time root password to an untracked project-local file.
  --keep-public-ssh      Pass through to the VPS installer; not recommended long-term.
  -y, --yes              Accept non-destructive prompts. Paid server creation still asks once.
  -h, --help             Show this help.

Environment overrides:
  HETZNER_API_TOKEN      Hetzner Cloud API token.
  MODEL_PROVIDER         Model provider identifier.
  MODEL_BASE_URL         OpenAI-compatible model API base URL.
  MODEL_API_KEY          Model provider API key.
  MODEL_ID               Default model reference.
  TAILSCALE_AUTH_KEY     Optional Tailscale auth key forwarded to the VPS installer.
  TELEGRAM_BOT_TOKEN     Optional Telegram bot token.
  TELEGRAM_ALLOWED_USERS Optional numeric Telegram user ID allowlist.
  HERMES_TERMINAL_BACKEND
                          Hermes terminal backend on the VPS. Default: local.
  HERMES_SUDO_NOPASSWD   Set to 1 for passwordless sudo in the trusted-owner POC.
  HERMES_SSH_KEY_PASSPHRASE
                          Optional SSH key passphrase for noninteractive testing.
  HETZNER_LOCATION       Default: fsn1.
  HETZNER_SERVER_TYPE    Default: cx23.
  HETZNER_IMAGE          Default: ubuntu-24.04.
  HETZNER_SERVER_NAME    Default: hermes-YYYYMMDD-HHMMSS.
  HERMES_VPS_URL         Remote VPS installer URL.
  HERMES_TIMEZONE        IANA timezone. Default: your local machine's current timezone, then UTC.
USAGE
}

log() {
  printf '[hermes-hetzner] %s\n' "$*"
}

warn() {
  printf '[hermes-hetzner] warning: %s\n' "$*" >&2
}

fail() {
  printf '[hermes-hetzner] error: %s\n' "$*" >&2
  if [[ -n "$CREATED_SERVER_ID" || -n "$CREATED_SERVER_IP" ]]; then
    printf '\nA Hetzner server may have been created and was not destroyed automatically.\n' >&2
    printf '  Server ID: %s\n' "${CREATED_SERVER_ID:-unknown}" >&2
    printf '  Public IP: %s\n' "${CREATED_SERVER_IP:-unknown}" >&2
    printf 'Delete it in Hetzner Cloud if you do not want to keep paying for it.\n' >&2
  fi
  exit 1
}

confirm() {
  local prompt="$1"
  local answer=""
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
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

prompt_required_value() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"
  if [[ -n "$current" ]]; then
    printf '%s' "$current"
    return 0
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "${prompt}: " value
  done
  printf '%s' "$value"
}

shell_quote() {
  printf '%q' "$1"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_or_offer_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  fail "jq is required. Install it with your system package manager, then rerun."
}

check_local_dependencies() {
  need_command curl
  need_command ssh
  need_command ssh-add
  need_command ssh-agent
  need_command ssh-keygen
  require_or_offer_jq
}

cleanup_temp_ssh_agent() {
  if [[ "$TEMP_SSH_AGENT_STARTED" == "1" ]]; then
    ssh-agent -k >/dev/null 2>&1 || true
  fi
}

generate_root_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24 | cut -c1-32
    return 0
  fi
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

detect_current_timezone() {
  local timezone=""
  if command -v systemsetup >/dev/null 2>&1; then
    timezone="$(systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}' || true)"
  fi
  if [[ -z "$timezone" && -L /etc/localtime ]]; then
    timezone="$(readlink /etc/localtime | sed 's#^.*zoneinfo/##' || true)"
  fi
  printf '%s' "${timezone:-UTC}"
}

choose_or_create_ssh_key() {
  if [[ -n "$SSH_PUBLIC_KEY_PATH" ]]; then
    SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"
  elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    SSH_PUBLIC_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
  elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
    SSH_PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"
  else
    if confirm "No SSH public key found. Create ~/.ssh/id_ed25519 now?"; then
      install -d -m 0700 "$HOME/.ssh"
      ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "hermes-hetzner-$(whoami)@$(hostname)"
      SSH_PUBLIC_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
    else
      fail "SSH key is required. Create one with: ssh-keygen -t ed25519"
    fi
  fi

  [[ -r "$SSH_PUBLIC_KEY_PATH" ]] || fail "SSH public key not readable: $SSH_PUBLIC_KEY_PATH"
  SSH_PRIVATE_KEY_PATH="${SSH_PUBLIC_KEY_PATH%.pub}"
  [[ -r "$SSH_PRIVATE_KEY_PATH" ]] || fail "SSH private key not readable: $SSH_PRIVATE_KEY_PATH"
  log "using SSH public key: $SSH_PUBLIC_KEY_PATH"
}

add_ssh_key_with_passphrase() {
  local passphrase="$1"
  local askpass_dir askpass_file
  askpass_dir="$(mktemp -d)"
  askpass_file="${askpass_dir}/askpass.sh"
  cat >"$askpass_file" <<'ASKPASS'
#!/usr/bin/env bash
printf '%s\n' "$HERMES_SSH_KEY_PASSPHRASE"
ASKPASS
  chmod 700 "$askpass_file"
  if ! HERMES_SSH_KEY_PASSPHRASE="$passphrase" DISPLAY="hermes" SSH_ASKPASS="$askpass_file" SSH_ASKPASS_REQUIRE=force ssh-add "$SSH_PRIVATE_KEY_PATH" </dev/null >/dev/null; then
    rm -rf "$askpass_dir"
    fail "could not add SSH key to agent; passphrase may be incorrect"
  fi
  rm -rf "$askpass_dir"
}

load_selected_ssh_key() {
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
    TEMP_SSH_AGENT_STARTED=1
  fi
  if ssh-add "$SSH_PRIVATE_KEY_PATH" </dev/null >/dev/null 2>&1; then
    return 0
  fi
  if [[ -z "$HERMES_SSH_KEY_PASSPHRASE" ]]; then
    HERMES_SSH_KEY_PASSPHRASE="$(prompt_secret HERMES_SSH_KEY_PASSPHRASE 'Private SSH key passphrase' required)"
  fi
  if ! ssh-keygen -y -P "$HERMES_SSH_KEY_PASSPHRASE" -f "$SSH_PRIVATE_KEY_PATH" >/dev/null 2>&1; then
    fail "SSH key passphrase is incorrect for $SSH_PRIVATE_KEY_PATH (key/passphrase drift?). Verify with: ssh-keygen -y -P '<passphrase>' -f $SSH_PRIVATE_KEY_PATH"
  fi
  add_ssh_key_with_passphrase "$HERMES_SSH_KEY_PASSPHRASE"
}

hcloud_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local auth_header rc
  auth_header="$(mktemp)"
  chmod 600 "$auth_header"
  printf 'Authorization: Bearer %s\n' "$HETZNER_API_TOKEN" >"$auth_header"
  rc=0
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" \
      -H @"$auth_header" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${HETZNER_API_BASE}${path}" || rc=$?
  else
    curl -fsS -X "$method" \
      -H @"$auth_header" \
      "${HETZNER_API_BASE}${path}" || rc=$?
  fi
  rm -f "$auth_header"
  return "$rc"
}

hcloud_api_allow_conflict() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local output status
  if [[ -n "$data" ]]; then
    output="$(curl -sS -w '\n%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${HETZNER_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${HETZNER_API_BASE}${path}")"
  else
    output="$(curl -sS -w '\n%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${HETZNER_API_TOKEN}" \
      "${HETZNER_API_BASE}${path}")"
  fi
  status="${output##*$'\n'}"
  output="${output%$'\n'*}"
  printf '%s\n%s' "$status" "$output"
}

normalized_ssh_public_key() {
  awk '{print $1 " " $2}' "$1"
}

find_hetzner_ssh_key_id() {
  local public_key="$1"
  local response
  response="$(hcloud_api GET "/ssh_keys")"
  jq -r --arg public_key "$public_key" '.ssh_keys[] | select((.public_key | split(" ")[0:2] | join(" ")) == $public_key) | .id' <<<"$response" | head -n 1
}

ensure_hetzner_ssh_key() {
  local public_key existing_id key_name payload response status body
  public_key="$(normalized_ssh_public_key "$SSH_PUBLIC_KEY_PATH")"
  existing_id="$(find_hetzner_ssh_key_id "$public_key")"
  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    printf '[hermes-hetzner] reusing existing Hetzner SSH key id %s\n' "$existing_id" >&2
    printf '%s' "$existing_id"
    return 0
  fi

  key_name="hermes-$(whoami)-$(date +%Y%m%d-%H%M%S)"
  payload="$(jq -nc --arg name "$key_name" --arg public_key "$public_key" '{"name":$name,"public_key":$public_key}')"
  response="$(hcloud_api_allow_conflict POST "/ssh_keys" "$payload")"
  status="${response%%$'\n'*}"
  body="${response#*$'\n'}"
  if [[ "$status" == "201" || "$status" == "200" ]]; then
    jq -r '.ssh_key.id' <<<"$body"
    return 0
  fi
  if [[ "$status" == "409" ]]; then
    printf '[hermes-hetzner] SSH key already exists in Hetzner; refetching existing SSH key\n' >&2
    existing_id="$(find_hetzner_ssh_key_id "$public_key")"
    [[ -n "$existing_id" && "$existing_id" != "null" ]] || fail "Hetzner reported duplicate SSH key but it could not be found"
    printf '%s' "$existing_id"
    return 0
  fi
  printf '%s\n' "$body" >&2
  fail "Hetzner SSH key create failed with HTTP ${status}"
}

create_hetzner_server() {
  local ssh_key_id="$1"
  local payload response status body
  payload="$(jq -nc \
    --arg name "$HETZNER_SERVER_NAME" \
    --arg server_type "$HETZNER_SERVER_TYPE" \
    --arg image "$HETZNER_IMAGE" \
    --arg location "$HETZNER_LOCATION" \
    --argjson ssh_key "$ssh_key_id" \
    '{"name":$name,"server_type":$server_type,"image":$image,"location":$location,"ssh_keys":[$ssh_key],"start_after_create":true}')"

  response="$(hcloud_api_allow_conflict POST "/servers" "$payload")"
  status="${response%%$'\n'*}"
  body="${response#*$'\n'}"
  if [[ "$status" != "201" && "$status" != "200" ]]; then
    printf '%s\n' "$body" >&2
    fail "Hetzner server create failed with HTTP ${status}"
  fi

  CREATED_SERVER_ID="$(jq -r '.server.id' <<<"$body")"
  CREATED_SERVER_IP="$(jq -r '.server.public_net.ipv4.ip // empty' <<<"$body")"
  [[ -n "$CREATED_SERVER_ID" && "$CREATED_SERVER_ID" != "null" ]] || fail "Hetzner did not return a server id"
  log "created server id ${CREATED_SERVER_ID}"
  if [[ -n "$CREATED_SERVER_IP" ]]; then
    log "server public IPv4: ${CREATED_SERVER_IP}"
  fi
}

wait_for_server_running() {
  log "waiting for Hetzner server to become running"
  local response status ip attempt
  for attempt in {1..90}; do
    response="$(hcloud_api GET "/servers/${CREATED_SERVER_ID}")"
    status="$(jq -r '.server.status' <<<"$response")"
    ip="$(jq -r '.server.public_net.ipv4.ip // empty' <<<"$response")"
    if [[ "$status" == "running" && -n "$ip" ]]; then
      CREATED_SERVER_IP="$ip"
      log "server is running at ${CREATED_SERVER_IP}"
      return 0
    fi
    sleep 5
  done
  fail "server did not become running in time"
}

forget_stale_server_host_key() {
  if [[ -f "$HOME/.ssh/known_hosts" ]]; then
    ssh-keygen -R "$CREATED_SERVER_IP" >/dev/null 2>&1 || true
  fi
}

ssh_opts() {
  printf '%s\n' \
    -i "$SSH_PRIVATE_KEY_PATH" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5
}

wait_for_ssh() {
  log "waiting for root SSH on ${CREATED_SERVER_IP}"
  forget_stale_server_host_key
  local attempt
  for attempt in {1..90}; do
    if ssh $(ssh_opts) "root@${CREATED_SERVER_IP}" "true" >/dev/null 2>&1; then
      log "root SSH is ready"
      return 0
    fi
    if (( attempt % 6 == 0 )); then
      log "still waiting for root SSH on ${CREATED_SERVER_IP} (${attempt}/90 attempts)"
    fi
    sleep 5
  done
  fail "SSH did not become reachable in time; try manually: ssh root@${CREATED_SERVER_IP}"
}

set_remote_root_password() {
  log "setting generated root password on the server"
  printf 'root:%s\n' "$ROOT_PASSWORD" | ssh $(ssh_opts) "root@${CREATED_SERVER_IP}" "chpasswd"
}

write_remote_env_file() {
  local env_contents
  env_contents="MODEL_PROVIDER=$(shell_quote "$MODEL_PROVIDER")"$'\n'
  env_contents+="MODEL_BASE_URL=$(shell_quote "$MODEL_BASE_URL")"$'\n'
  env_contents+="MODEL_API_KEY=$(shell_quote "$MODEL_API_KEY")"$'\n'
  env_contents+="MODEL_ID=$(shell_quote "$MODEL_ID")"$'\n'
  env_contents+="HERMES_TIMEZONE=$(shell_quote "$HERMES_TIMEZONE")"$'\n'
  env_contents+="HERMES_TERMINAL_BACKEND=$(shell_quote "$HERMES_TERMINAL_BACKEND")"$'\n'
  env_contents+="HERMES_SUDO_NOPASSWD=$(shell_quote "$HERMES_SUDO_NOPASSWD")"$'\n'
  if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
    env_contents+="TELEGRAM_BOT_TOKEN=$(shell_quote "$TELEGRAM_BOT_TOKEN")"$'\n'
  fi
  if [[ -n "$TELEGRAM_ALLOWED_USERS" ]]; then
    env_contents+="TELEGRAM_ALLOWED_USERS=$(shell_quote "$TELEGRAM_ALLOWED_USERS")"$'\n'
  fi
  if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
    env_contents+="TAILSCALE_AUTH_KEY=$(shell_quote "$TAILSCALE_AUTH_KEY")"$'\n'
  fi
  ssh $(ssh_opts) "root@${CREATED_SERVER_IP}" "umask 077; cat >/root/hermes-vps.env" <<<"$env_contents"
}

run_remote_installer() {
  local keep_public_ssh_arg=""
  local remote_installer_url
  if [[ "$KEEP_PUBLIC_SSH" == "1" ]]; then
    keep_public_ssh_arg="--keep-public-ssh"
  fi
  log "downloading and running remote Hermes VPS installer"
  write_remote_env_file
  if [[ -r "${SCRIPT_DIR}/hermes-vps.sh" ]]; then
    log "uploading local hermes-vps.sh"
    scp $(ssh_opts) "${SCRIPT_DIR}/hermes-vps.sh" "root@${CREATED_SERVER_IP}:/root/hermes-vps.sh"
    printf '\n\n\n\n' | ssh -tt $(ssh_opts) "root@${CREATED_SERVER_IP}" \
      "chmod +x /root/hermes-vps.sh && set -a && . /root/hermes-vps.env && set +a && /root/hermes-vps.sh install ${keep_public_ssh_arg}"
  else
    remote_installer_url="$(shell_quote "${HERMES_VPS_URL}?$(date +%s)")"
    printf '\n\n\n\n' | ssh -tt $(ssh_opts) "root@${CREATED_SERVER_IP}" \
      "curl -fsSL ${remote_installer_url} -o /root/hermes-vps.sh && chmod +x /root/hermes-vps.sh && set -a && . /root/hermes-vps.env && set +a && /root/hermes-vps.sh install ${keep_public_ssh_arg}"
  fi
}

detect_remote_tailscale_ip() {
  log "detecting server Tailscale IP"
  CREATED_SERVER_TAILSCALE_IP="$(ssh $(ssh_opts) "root@${CREATED_SERVER_IP}" "tailscale ip -4 | head -n 1")"
  [[ -n "$CREATED_SERVER_TAILSCALE_IP" ]] || fail "could not detect server Tailscale IP"
  log "server Tailscale IP: ${CREATED_SERVER_TAILSCALE_IP}"
}

run_remote_lockdown() {
  local keep_public_ssh_arg=""
  if [[ "$KEEP_PUBLIC_SSH" == "1" ]]; then
    keep_public_ssh_arg="--keep-public-ssh"
  fi
  log "applying remote lockdown over Tailscale"
  printf 'LOCKDOWN\n' | ssh -tt $(ssh_opts) "root@${CREATED_SERVER_TAILSCALE_IP}" "/root/hermes-vps.sh lockdown ${keep_public_ssh_arg}"
}

verify_remote_lockdown() {
  log "verifying remote lockdown over Tailscale"
  ssh $(ssh_opts) "root@${CREATED_SERVER_TAILSCALE_IP}" "ufw status verbose; /root/hermes-vps.sh status >/dev/null"
}

collect_inputs() {
  HETZNER_API_TOKEN="$(prompt_secret HETZNER_API_TOKEN 'Hetzner Cloud API token' required)"
  MODEL_PROVIDER="$(prompt_required_value MODEL_PROVIDER 'Model provider id')"
  MODEL_BASE_URL="$(prompt_required_value MODEL_BASE_URL 'Model API base URL')"
  MODEL_API_KEY="$(prompt_secret MODEL_API_KEY 'Model API key' required)"
  MODEL_ID="$(prompt_required_value MODEL_ID 'Default model (format: provider/model-id)')"
  HERMES_TIMEZONE="${HERMES_TIMEZONE:-$(detect_current_timezone)}"
  TELEGRAM_BOT_TOKEN="$(prompt_secret TELEGRAM_BOT_TOKEN 'Telegram bot token' optional)"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -z "$TELEGRAM_ALLOWED_USERS" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist (leave empty for pairing flow): ' TELEGRAM_ALLOWED_USERS
  fi
}

confirm_paid_server_create() {
  printf '\nThis will create a new paid Hetzner Cloud server:\n'
  printf '  Name:        %s\n' "$HETZNER_SERVER_NAME"
  printf '  Location:    %s\n' "$HETZNER_LOCATION"
  printf '  Server type: %s\n' "$HETZNER_SERVER_TYPE"
  printf '  Image:       %s\n' "$HETZNER_IMAGE"
  printf '\nHetzner will bill this server until you delete it.\n'
  local answer=""
  read -r -p 'Type CREATE to continue: ' answer
  [[ "$answer" == "CREATE" ]] || fail "server creation cancelled — type CREATE to continue"
}

print_summary() {
  if [[ -n "$CREDENTIALS_FILE" ]]; then
    local project_dir credentials_path credentials_dir relative_path
    project_dir="$(pwd -P)"
    credentials_path="$CREDENTIALS_FILE"
    [[ "$credentials_path" == /* ]] || credentials_path="$project_dir/$credentials_path"
    credentials_dir="$(dirname "$credentials_path")"
    [[ -d "$credentials_dir" ]] || fail "credentials file directory does not exist: $credentials_dir"
    credentials_path="$(cd "$credentials_dir" && pwd -P)/$(basename "$credentials_path")"
    [[ "$credentials_path" == "$project_dir/"* ]] || fail "credentials file must be inside project directory: $project_dir"
    [[ ! -L "$credentials_path" ]] || fail "refusing symlink credentials file: $CREDENTIALS_FILE"
    relative_path="${credentials_path#"$project_dir/"}"
    if git -C "$project_dir" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
      fail "refusing tracked credentials file: $CREDENTIALS_FILE"
    fi
    (
      umask 177
      printf 'ROOT_PASSWORD=%s\n' "$ROOT_PASSWORD" >"$credentials_path"
      chmod 600 "$credentials_path"
    )
    printf 'saved root password to %s\n' "$CREDENTIALS_FILE"
  fi
  printf '\nHermes Hetzner setup finished.\n'
  printf '  Server name: %s\n' "$HETZNER_SERVER_NAME"
  printf '  Server ID:   %s\n' "$CREATED_SERVER_ID"
  printf '  Public IP:   %s\n' "$CREATED_SERVER_IP"
  printf '  Tailscale IP:%s\n' " ${CREATED_SERVER_TAILSCALE_IP}"
  printf '  Timezone:    %s\n' "$HERMES_TIMEZONE"
  printf '\nSSH via Tailscale:\n'
  printf '  SSH key: %s\n' "$SSH_PRIVATE_KEY_PATH"
  printf '  ssh root@%s\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '\nRemote commands:\n'
  printf '  ssh root@%s /root/hermes-vps.sh status\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/hermes-vps.sh doctor\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/hermes-vps.sh refresh-config\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/hermes-vps.sh logs\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '\nPublic SSH is locked down; use the Tailscale IP above.\n'
  printf '\n\n============================================================\n'
  printf '              SAVE THIS ROOT PASSWORD NOW\n'
  printf '============================================================\n'
  printf 'VPS: %s\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf 'User: root\n'
  printf 'Root password: %s\n' "$ROOT_PASSWORD"
  printf 'SSH key: %s\n' "$SSH_PRIVATE_KEY_PATH"
  printf '============================================================\n'
  printf 'This password is printed once and is not saved by this script.\n'
  printf 'Store it in your password manager before closing this terminal.\n'
  printf '============================================================\n\n'
}

print_existing_host_group_summary() {
  [[ "$COMMAND" == "add-group" ]] || return 0
  printf '\nHermes group setup finished.\n'
  printf '  Host:        %s\n' "$REMOTE_HOST"
  printf '  Group:       %s\n' "$HERMES_GROUP"
  printf '  SSH key:     %s\n' "$SSH_PRIVATE_KEY_PATH"
  printf '\nNo new root password was generated for this group. Use the VPS root password printed during the original server install, your SSH key, or provider console recovery.\n'
  printf '\nSSH via Tailscale:\n'
  printf '  ssh root@%s\n' "$REMOTE_HOST"
  printf '\nGroup commands:\n'
  printf '  ssh root@%s /root/hermes-vps.sh --group %s status\n' "$REMOTE_HOST" "$HERMES_GROUP"
  printf '  ssh root@%s /root/hermes-vps.sh --group %s doctor\n' "$REMOTE_HOST" "$HERMES_GROUP"
  printf '  ssh root@%s /root/hermes-vps.sh --group %s logs\n' "$REMOTE_HOST" "$HERMES_GROUP"
}

cmd_preflight() {
  local failures=0 pub_path priv_path available response cmd
  for cmd in curl ssh ssh-add ssh-keygen jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log "preflight OK: $cmd present"
    else
      warn "preflight FAIL: required command not found: $cmd"
      failures=$((failures + 1))
    fi
  done
  if [[ "${#HETZNER_API_TOKEN}" -ge 20 ]]; then
    log "preflight OK: Hetzner API token present"
  else
    warn "preflight FAIL: Hetzner API token missing or shorter than 20 characters"
    failures=$((failures + 1))
  fi
  pub_path="${SSH_PUBLIC_KEY_PATH/#\~/$HOME}"
  priv_path="${pub_path%.pub}"
  if [[ -n "$pub_path" && -r "$pub_path" && -r "$priv_path" ]]; then
    log "preflight OK: SSH key pair readable"
  else
    warn "preflight FAIL: SSH key pair not readable (public: ${pub_path:-unset})"
    failures=$((failures + 1))
  fi
  if [[ -r "$priv_path" ]]; then
    if ssh-keygen -y -P "" -f "$priv_path" >/dev/null 2>&1; then
      log "preflight OK: private key needs no passphrase"
    elif [[ -n "${HERMES_SSH_KEY_PASSPHRASE:-}" ]]; then
      if ssh-keygen -y -P "$HERMES_SSH_KEY_PASSPHRASE" -f "$priv_path" >/dev/null 2>&1; then
        log "preflight OK: SSH key passphrase verified"
      else
        warn "preflight FAIL: SSH key passphrase is incorrect (key/passphrase drift?)"
        failures=$((failures + 1))
      fi
    else
      warn "preflight WARN: private key is encrypted and no passphrase is set; install will prompt"
    fi
  fi
  if [[ -n "$HETZNER_API_TOKEN" ]]; then
    response="$(hcloud_api GET "/server_types" 2>/dev/null || true)"
    available="$(jq -r --arg t "$HETZNER_SERVER_TYPE" '[.server_types[]? | select(.name == $t) | .locations[]? | if type == "object" then (select(.available == true) | .name) else . end] | unique | join(" ")' <<<"$response" 2>/dev/null || true)"
    if [[ -z "$available" ]]; then
      warn "preflight FAIL: no available location data for server type $HETZNER_SERVER_TYPE"
      failures=$((failures + 1))
    elif [[ " $available " == *" $HETZNER_LOCATION "* ]]; then
      log "preflight OK: $HETZNER_SERVER_TYPE available in $HETZNER_LOCATION"
    else
      warn "preflight FAIL: location $HETZNER_LOCATION not available for $HETZNER_SERVER_TYPE; available: $available"
      failures=$((failures + 1))
    fi
  fi
  if [[ -n "${MODEL_API_KEY:-}" ]]; then
    if [[ "${#MODEL_API_KEY}" -ge 20 ]]; then
      log "preflight OK: provider model API key present"
    else
      warn "preflight FAIL: provider model API key looks truncated (shorter than 20 characters)"
      failures=$((failures + 1))
    fi
  else
    warn "preflight WARN: provider model API key unset; install will prompt"
  fi
  if (( failures > 0 )); then
    fail "preflight found $failures problem(s); fix before installing"
  fi
  log "preflight OK: all checks passed"
}

run_install() {
  collect_inputs
  choose_or_create_ssh_key
  cmd_preflight
  load_selected_ssh_key
  confirm_paid_server_create
  local ssh_key_id
  ssh_key_id="$(ensure_hetzner_ssh_key)" || fail "could not create or reuse Hetzner SSH key"
  create_hetzner_server "$ssh_key_id"
  wait_for_server_running
  wait_for_ssh
  ROOT_PASSWORD="$(generate_root_password)"
  set_remote_root_password
  run_remote_installer
  detect_remote_tailscale_ip
  run_remote_lockdown
  verify_remote_lockdown
  print_summary
}

run_existing_host_command() {
  [[ -n "$REMOTE_HOST" ]] || fail "--host is required for ${COMMAND}"
  choose_or_create_ssh_key
  load_selected_ssh_key
  local group_args=""
  local secret_args=""
  if [[ -n "$HERMES_GROUP" ]]; then
    group_args="--group $(shell_quote "$HERMES_GROUP") "
  fi
  if [[ -n "$HERMES_GROUP_MODEL_API_KEY" ]]; then
    secret_args+=" --model-api-key $(shell_quote "$HERMES_GROUP_MODEL_API_KEY")"
  fi
  if [[ -n "$HERMES_GROUP_TELEGRAM_BOT_TOKEN" ]]; then
    secret_args+=" --telegram-bot-token $(shell_quote "$HERMES_GROUP_TELEGRAM_BOT_TOKEN")"
  fi
  if [[ -n "$HERMES_GROUP_TELEGRAM_ALLOWED_USERS" ]]; then
    secret_args+=" --telegram-allow-from $(shell_quote "$HERMES_GROUP_TELEGRAM_ALLOWED_USERS")"
  fi
  local remote_command
  case "$COMMAND" in
    add-group)
      remote_command="/root/hermes-vps.sh ${group_args}add-group${secret_args}"
      ;;
    status|doctor|refresh-config|backup|maintenance|logs)
      remote_command="/root/hermes-vps.sh ${group_args}${COMMAND}"
      ;;
    *)
      fail "unsupported existing-host command: ${COMMAND}"
      ;;
  esac
  log "running ${COMMAND} on existing host ${REMOTE_HOST}"
  printf '\n\n\n\n' | ssh -tt $(ssh_opts) "root@${REMOTE_HOST}" "$remote_command"
  print_existing_host_group_summary
}

parse_args() {
  if (($#)); then
    case "$1" in
      preflight|install|add-group|status|doctor|refresh-config|backup|maintenance|logs)
        COMMAND="$1"
        shift
        ;;
      help|-h|--help)
        usage
        exit 0
        ;;
    esac
  fi
  while (($#)); do
    case "$1" in
      --server-name)
        [[ -n "${2:-}" ]] || fail "--server-name requires a value"
        HETZNER_SERVER_NAME="$2"
        shift 2
        ;;
      --host)
        [[ -n "${2:-}" ]] || fail "--host requires a value"
        REMOTE_HOST="$2"
        shift 2
        ;;
      --group)
        [[ -n "${2:-}" ]] || fail "--group requires a value"
        HERMES_GROUP="$2"
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
      --ssh-key)
        [[ -n "${2:-}" ]] || fail "--ssh-key requires a value"
        SSH_PUBLIC_KEY_PATH="$2"
        shift 2
        ;;
      --credentials-file)
        [[ -n "${2:-}" ]] || fail "--credentials-file requires a value"
        CREDENTIALS_FILE="$2"
        shift 2
        ;;
      --keep-public-ssh)
        KEEP_PUBLIC_SSH=1
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      help|-h|--help)
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
  trap cleanup_temp_ssh_agent EXIT
  parse_args "$@"
  check_local_dependencies
  case "$COMMAND" in
    preflight)
      cmd_preflight
      ;;
    install)
      run_install
      ;;
    add-group|status|doctor|refresh-config|backup|maintenance|logs)
      run_existing_host_command
      ;;
    *)
      fail "unknown command: ${COMMAND}"
      ;;
  esac
}

main "$@"
