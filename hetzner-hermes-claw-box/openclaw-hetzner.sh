#!/usr/bin/env bash
set -Eeuo pipefail

HETZNER_LOCATION="${HETZNER_LOCATION:-fsn1}"
HETZNER_SERVER_TYPE="${HETZNER_SERVER_TYPE:-cx23}"
HETZNER_IMAGE="${HETZNER_IMAGE:-ubuntu-24.04}"
HETZNER_SERVER_NAME="${HETZNER_SERVER_NAME:-openclaw-$(date +%Y%m%d-%H%M%S)}"
HETZNER_API_BASE="https://api.hetzner.cloud/v1"
OPENCLAW_VPS_URL="${OPENCLAW_VPS_URL:-https://raw.githubusercontent.com/ceckenrode/chriseckenrode-skills/main/hetzner-hermes-claw-box/scripts/openclaw-vps.sh}"
OPENCLAW_TIMEZONE="${OPENCLAW_TIMEZONE:-}"

COMMAND="install"
ASSUME_YES=0
KEEP_PUBLIC_SSH=0
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-}"
SSH_PRIVATE_KEY_PATH=""
CREDENTIALS_FILE="${CREDENTIALS_FILE:-}"
REMOTE_HOST=""
GROUP_ID=""
AGENT_ID=""
OPENCLAW_INITIAL_AGENT_ID="${OPENCLAW_INITIAL_AGENT_ID:-}"
OPENCLAW_INITIAL_AGENT_LABEL="${OPENCLAW_INITIAL_AGENT_LABEL:-}"
HETZNER_API_TOKEN="${HETZNER_API_TOKEN:-}"
MODEL_PROVIDER="${MODEL_PROVIDER:-}"
MODEL_BASE_URL="${MODEL_BASE_URL:-}"
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_ID="${MODEL_ID:-}"
MODEL_CATALOG="${MODEL_CATALOG:-}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ALLOW_FROM="${TELEGRAM_ALLOW_FROM:-}"
OPENCLAW_SSH_KEY_PASSPHRASE="${OPENCLAW_SSH_KEY_PASSPHRASE:-}"
CREATED_SERVER_ID=""
CREATED_SERVER_IP=""
CREATED_SERVER_TAILSCALE_IP=""
ROOT_PASSWORD=""
TEMP_SSH_AGENT_STARTED=0

usage() {
  cat <<'USAGE'
Usage: ./openclaw-hetzner.sh [command] [options]

Create a new Hetzner Cloud server from your computer and install OpenClaw on it.

Commands:
  install                Create a new Hetzner Cloud server and install OpenClaw. Default.
  preflight              Validate tools, credentials, and server capacity before install.
  add-group              Add an Incus isolation group on an existing OpenClaw VPS.
  add-agent              Add an OpenClaw agent on an existing OpenClaw VPS.

Defaults:
  - location: fsn1 (Falkenstein)
  - server type: cx23 (cheap shared x86)
  - image: ubuntu-24.04
  - Tailscale: browser login during remote install

Options:
  --server-name NAME     Override generated server name.
  --host HOST            Existing VPS Tailscale IP or hostname for add-group/add-agent.
  --group GROUP          Isolation group id for add-group/add-agent.
  --agent AGENT          Agent id for add-agent.
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
  MODEL_CATALOG          Optional comma-separated model refs; auto-discovered from the provider catalog endpoint when unset.
  TAILSCALE_AUTH_KEY     Optional Tailscale auth key forwarded to the VPS installer.
  TELEGRAM_BOT_TOKEN     Optional Telegram bot token.
  TELEGRAM_ALLOW_FROM    Optional numeric Telegram user ID allowlist.
  OPENCLAW_SSH_KEY_PASSPHRASE
                         Optional SSH key passphrase for noninteractive testing.
  HETZNER_LOCATION       Default: fsn1.
  HETZNER_SERVER_TYPE    Default: cx23.
  HETZNER_IMAGE          Default: ubuntu-24.04.
  HETZNER_SERVER_NAME    Default: openclaw-YYYYMMDD-HHMMSS.
  OPENCLAW_VPS_URL       Remote VPS installer URL.
  OPENCLAW_TIMEZONE      IANA timezone. Default: your local machine's current timezone, then UTC.
  OPENCLAW_INITIAL_AGENT_ID
                         Required lowercase ID for the initial OpenClaw agent.
  OPENCLAW_INITIAL_AGENT_LABEL
                         Optional display label for the initial agent; defaults to its ID.
USAGE
}

log() {
  printf '[openclaw-hetzner] %s\n' "$*"
}

warn() {
  printf '[openclaw-hetzner] warning: %s\n' "$*" >&2
}

fail() {
  printf '[openclaw-hetzner] error: %s\n' "$*" >&2
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

validate_initial_agent_identity() {
  [[ -n "$OPENCLAW_INITIAL_AGENT_ID" ]] || fail 'OPENCLAW_INITIAL_AGENT_ID is required for OpenClaw install'
  [[ "$OPENCLAW_INITIAL_AGENT_ID" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || \
    fail "invalid OpenClaw initial agent ID: $OPENCLAW_INITIAL_AGENT_ID"
  OPENCLAW_INITIAL_AGENT_LABEL="${OPENCLAW_INITIAL_AGENT_LABEL:-$OPENCLAW_INITIAL_AGENT_ID}"
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
      ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "openclaw-hetzner-$(whoami)@$(hostname)"
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
printf '%s\n' "$OPENCLAW_SSH_KEY_PASSPHRASE"
ASKPASS
  chmod 700 "$askpass_file"
  if ! OPENCLAW_SSH_KEY_PASSPHRASE="$passphrase" DISPLAY="openclaw" SSH_ASKPASS="$askpass_file" SSH_ASKPASS_REQUIRE=force ssh-add "$SSH_PRIVATE_KEY_PATH" </dev/null >/dev/null; then
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

  if [[ -z "$OPENCLAW_SSH_KEY_PASSPHRASE" ]]; then
    OPENCLAW_SSH_KEY_PASSPHRASE="$(prompt_secret OPENCLAW_SSH_KEY_PASSPHRASE 'Private SSH key passphrase' required)"
  fi
  if ! ssh-keygen -y -P "$OPENCLAW_SSH_KEY_PASSPHRASE" -f "$SSH_PRIVATE_KEY_PATH" >/dev/null 2>&1; then
    fail "SSH key passphrase is incorrect for $SSH_PRIVATE_KEY_PATH (key/passphrase drift?). Verify with: ssh-keygen -y -P '<passphrase>' -f $SSH_PRIVATE_KEY_PATH"
  fi
  add_ssh_key_with_passphrase "$OPENCLAW_SSH_KEY_PASSPHRASE"
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
    printf '[openclaw-hetzner] reusing existing Hetzner SSH key id %s\n' "$existing_id" >&2
    printf '%s' "$existing_id"
    return 0
  fi

  key_name="openclaw-$(whoami)-$(date +%Y%m%d-%H%M%S)"
  payload="$(jq -nc --arg name "$key_name" --arg public_key "$public_key" '{"name":$name,"public_key":$public_key}')"
  response="$(hcloud_api_allow_conflict POST "/ssh_keys" "$payload")"
  status="${response%%$'\n'*}"
  body="${response#*$'\n'}"
  if [[ "$status" == "201" || "$status" == "200" ]]; then
    jq -r '.ssh_key.id' <<<"$body"
    return 0
  fi
  if [[ "$status" == "409" ]]; then
    printf '[openclaw-hetzner] SSH key already exists in Hetzner; refetching existing SSH key\n' >&2
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

print_root_password_once() {
  printf '\nROOT PASSWORD (printed once; not saved by this script):\n'
  printf '  %s\n\n' "$ROOT_PASSWORD"
}

write_remote_env_file() {
  local env_contents
  env_contents="MODEL_PROVIDER=$(shell_quote "$MODEL_PROVIDER")"$'\n'
  env_contents+="MODEL_BASE_URL=$(shell_quote "$MODEL_BASE_URL")"$'\n'
  env_contents+="MODEL_API_KEY=$(shell_quote "$MODEL_API_KEY")"$'\n'
  env_contents+="MODEL_ID=$(shell_quote "$MODEL_ID")"$'\n'
  env_contents+="OPENCLAW_INITIAL_AGENT_ID=$(shell_quote "$OPENCLAW_INITIAL_AGENT_ID")"$'\n'
  env_contents+="OPENCLAW_INITIAL_AGENT_LABEL=$(shell_quote "$OPENCLAW_INITIAL_AGENT_LABEL")"$'\n'
  if [[ -n "$MODEL_CATALOG" ]]; then
    env_contents+="MODEL_CATALOG=$(shell_quote "$MODEL_CATALOG")"$'\n'
  fi
  env_contents+="OPENCLAW_TIMEZONE=$(shell_quote "$OPENCLAW_TIMEZONE")"$'\n'
  if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
    env_contents+="TELEGRAM_BOT_TOKEN=$(shell_quote "$TELEGRAM_BOT_TOKEN")"$'\n'
  fi
  if [[ -n "$TELEGRAM_ALLOW_FROM" ]]; then
    env_contents+="TELEGRAM_ALLOW_FROM=$(shell_quote "$TELEGRAM_ALLOW_FROM")"$'\n'
  fi
  if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
    env_contents+="TAILSCALE_AUTH_KEY=$(shell_quote "$TAILSCALE_AUTH_KEY")"$'\n'
  fi

  ssh $(ssh_opts) "root@${CREATED_SERVER_IP}" "umask 077; cat >/root/openclaw-vps.env" <<<"$env_contents"
}

run_remote_installer() {
  local keep_public_ssh_arg=""
  local local_installer remote_command
  if [[ "$KEEP_PUBLIC_SSH" == "1" ]]; then
    keep_public_ssh_arg="--keep-public-ssh"
  fi

  write_remote_env_file
  local_installer="$(cd "$(dirname "$0")" && pwd)/openclaw-vps.sh"
  if [[ -f "$local_installer" ]]; then
    log "using local openclaw-vps.sh from repo"
    scp $(ssh_opts) "$local_installer" "root@${CREATED_SERVER_IP}:/root/openclaw-vps.sh"
    remote_command="chmod +x /root/openclaw-vps.sh && set -a && . /root/openclaw-vps.env && set +a && /root/openclaw-vps.sh install ${keep_public_ssh_arg}"
  else
    local remote_installer_url
    log "downloading and running remote OpenClaw VPS installer"
    remote_installer_url="$(shell_quote "${OPENCLAW_VPS_URL}?$(date +%s)")"
    remote_command="curl -fsSL ${remote_installer_url} -o /root/openclaw-vps.sh && chmod +x /root/openclaw-vps.sh && set -a && . /root/openclaw-vps.env && set +a && /root/openclaw-vps.sh install ${keep_public_ssh_arg}"
  fi
  printf '\n\n\n\n' | ssh -tt $(ssh_opts) "root@${CREATED_SERVER_IP}" "$remote_command"
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
  printf 'LOCKDOWN\n' | ssh -tt $(ssh_opts) "root@${CREATED_SERVER_TAILSCALE_IP}" "/root/openclaw-vps.sh lockdown ${keep_public_ssh_arg}"
}

verify_remote_lockdown() {
  log "verifying remote lockdown over Tailscale"
  ssh $(ssh_opts) "root@${CREATED_SERVER_TAILSCALE_IP}" "ufw status verbose; /root/openclaw-vps.sh status >/dev/null"
}

collect_inputs() {
  HETZNER_API_TOKEN="$(prompt_secret HETZNER_API_TOKEN 'Hetzner Cloud API token' required)"
  MODEL_PROVIDER="$(prompt_required_value MODEL_PROVIDER 'Model provider id')"
  MODEL_BASE_URL="$(prompt_required_value MODEL_BASE_URL 'Model API base URL')"
  MODEL_API_KEY="$(prompt_secret MODEL_API_KEY 'Model API key' required)"
  MODEL_ID="$(prompt_required_value MODEL_ID 'Default model (format: provider/model-id)')"
  OPENCLAW_TIMEZONE="${OPENCLAW_TIMEZONE:-$(detect_current_timezone)}"
  TELEGRAM_BOT_TOKEN="$(prompt_secret TELEGRAM_BOT_TOKEN 'Telegram bot token' optional)"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -z "$TELEGRAM_ALLOW_FROM" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist (leave empty for pairing flow): ' TELEGRAM_ALLOW_FROM
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
  printf '\nOpenClaw Hetzner setup finished.\n'
  printf '  Server name: %s\n' "$HETZNER_SERVER_NAME"
  printf '  Server ID:   %s\n' "$CREATED_SERVER_ID"
  printf '  Public IP:   %s\n' "$CREATED_SERVER_IP"
  printf '  Tailscale IP:%s\n' " ${CREATED_SERVER_TAILSCALE_IP}"
  printf '  Timezone:    %s\n' "$OPENCLAW_TIMEZONE"
  printf '  Initial agent: %s\n' "$OPENCLAW_INITIAL_AGENT_ID"
  printf '  Initial agent workspace: /home/openclaw/workspace-%s\n' "$OPENCLAW_INITIAL_AGENT_ID"
  printf '  Registration: ./agent-box-manage.sh register --runtime openclaw --agent %q --group main\n' \
    "$OPENCLAW_INITIAL_AGENT_ID"
  printf '\nRoot password (printed once; not saved by this script):\n'
  printf '  %s\n' "$ROOT_PASSWORD"
  printf '\nSSH via Tailscale:\n'
  printf '  ssh root@%s\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '\nRemote commands:\n'
  printf '  ssh root@%s /root/openclaw-vps.sh status\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/openclaw-vps.sh doctor\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/openclaw-vps.sh logs\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/openclaw-vps.sh add-group coding\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '  ssh root@%s /root/openclaw-vps.sh add-agent reviewer --group coding\n' "$CREATED_SERVER_TAILSCALE_IP"
  printf '\nPublic SSH is locked down; use the Tailscale IP above.\n'
}

cmd_preflight() {
  validate_initial_agent_identity
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
    elif [[ -n "${OPENCLAW_SSH_KEY_PASSPHRASE:-}" ]]; then
      if ssh-keygen -y -P "$OPENCLAW_SSH_KEY_PASSPHRASE" -f "$priv_path" >/dev/null 2>&1; then
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
  validate_initial_agent_identity
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

  local remote_command
  case "$COMMAND" in
    add-group)
      [[ -n "$GROUP_ID" ]] || fail "--group is required for add-group"
      remote_command="/root/openclaw-vps.sh add-group $(shell_quote "$GROUP_ID")"
      ;;
    add-agent)
      [[ -n "$AGENT_ID" ]] || fail "--agent is required for add-agent"
      [[ -n "$GROUP_ID" ]] || fail "--group is required for add-agent"
      remote_command="/root/openclaw-vps.sh add-agent $(shell_quote "$AGENT_ID") --group $(shell_quote "$GROUP_ID")"
      ;;
    *)
      fail "unsupported existing-host command: ${COMMAND}"
      ;;
  esac

  log "running ${COMMAND} on existing host ${REMOTE_HOST}"
  printf '\n\n\n\n' | ssh -tt $(ssh_opts) "root@${REMOTE_HOST}" "$remote_command"
}

parse_args() {
  if (($#)); then
    case "$1" in
      preflight|install|add-group|add-agent)
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
        GROUP_ID="$2"
        shift 2
        ;;
      --agent)
        [[ -n "${2:-}" ]] || fail "--agent requires a value"
        AGENT_ID="$2"
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
    add-group|add-agent)
      run_existing_host_command
      ;;
    *)
      fail "unknown command: ${COMMAND}"
      ;;
  esac
}

main "$@"
