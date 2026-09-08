#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
ENV_FILE="${ENV_FILE:-}"
ENV_EXAMPLE_FILE="${ENV_EXAMPLE_FILE:-}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-}"
TEMP_FILE=""
SERVER_TYPES_FILE=""
AUTH_HEADER_FILE=""
MODEL_PROVIDER="${MODEL_PROVIDER:-}"
MODEL_BASE_URL="${MODEL_BASE_URL:-}"
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_ID="${MODEL_ID:-}"
cleanup() {
  for temp_file in "$TEMP_FILE" "$SERVER_TYPES_FILE" "$AUTH_HEADER_FILE"; do
    [[ -z "$temp_file" ]] || rm -f -- "$temp_file"
  done
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: setup-agent-box.sh [--project-dir DIR] [--env-file FILE]
                          [--env-example-file FILE] [--credentials-file FILE]

Ask Hermes or OpenClaw first, choose a Hetzner server type/location, then
prepare credentials, SSH keys, and bundled provisioning/management scripts.
Output files must be inside the target project. Existing secrets are preserved
unless you agree to replace them. This helper does not create a paid server.
Use a working directory outside skill folders; skill contents stay stateless.
SSH private keys must be outside the target project (for example, ~/.ssh/...).
After a successful install, run ./agent-box-manage.sh register to seed boxes.json.
Renamed from setup-hermes-env.
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
assert_runtime_directory() {
  local directory="$1"
  # Resolve existing ancestors physically, including symlinked output parents.
  while [[ ! -d "$directory" ]]; do directory="$(dirname -- "$directory")"; done
  directory="$(cd -- "$directory" && pwd -P)"
  while :; do
    [[ ! -f "$directory/SKILL.md" ]] || fail 'Runtime files must be outside skill folders; choose a separate --project-dir and output paths'
    [[ "$directory" != / ]] || break
    directory="$(dirname -- "$directory")"
  done
}
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project-dir|--env-file|--env-example-file|--credentials-file)
      [[ -n "${2:-}" ]] || fail "$1 requires a value"
      case "$1" in
        --project-dir) PROJECT_DIR="$2" ;;
        --env-file) ENV_FILE="$2" ;;
        --env-example-file) ENV_EXAMPLE_FILE="$2" ;;
        --credentials-file) CREDENTIALS_FILE="$2" ;;
      esac
      shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

# Prompts write only to stderr; values never include prompt text or newlines.
ask() {
  local label="$1" required="${2:-optional}" secret="${3:-no}" default="${4:-}"
  while :; do
    printf '%s: ' "$label" >&2
    if [[ "$secret" == yes ]]; then
      IFS= read -r -s REPLY || fail 'Input ended; setup cancelled'
      printf '\n' >&2
    else
      IFS= read -r REPLY || fail 'Input ended; setup cancelled'
    fi
    REPLY="${REPLY:-$default}"
    [[ "$required" != required || -n "$REPLY" ]] && return 0
    printf 'Value is required.\n' >&2
  done
}
yes_no() {
  ask "$1 [y/N]"
  [[ "$REPLY" == y || "$REPLY" == Y || "$REPLY" == yes ]]
}
env_line() { printf '%s=%q\n' "$1" "$2"; }

# Limit generated outputs to this project so every secret path can be ignored.
output_path() {
  local path="$1"
  [[ "$path" == /* ]] || path="$PROJECT_DIR/$path"
  [[ -d "$(dirname -- "$path")" ]] || fail "Missing output directory: $path"
  path="$(cd -- "$(dirname -- "$path")" && pwd -P)/$(basename -- "$path")"
  assert_runtime_directory "$(dirname -- "$path")"
  [[ "$path" == "$PROJECT_DIR/"* ]] || fail "Output must be inside $PROJECT_DIR"
  [[ ! -L "$path" ]] || fail "Refusing symlink output: $path"
  REPLY="$path"
}
refuse_tracked_path() {
  local path="$1" repo_root relative
  command -v git >/dev/null || return 0
  repo_root="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ "$path" == "$repo_root/"* ]] || return 0
  relative="${path#"$repo_root/"}"
  if git -C "$repo_root" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
    fail "Refusing already tracked output target: $path; ignore rules do not protect tracked files"
  fi
}
ignore_path() {
  local path="${1#"$PROJECT_DIR/"}" entry
  # Escape gitignore metacharacters, including spaces in custom output paths.
  path="${path//\\/\\\\}"; path="${path//\[/\\[}"
  path="${path//\*/\\*}"; path="${path//\?/\\?}"; path="${path// /\\ }"
  for entry in "/$path" "/$path.*"; do
    if ! grep -qxF -- "$entry" "$PROJECT_DIR/.gitignore"; then
      printf '%s\n' "$entry" >> "$PROJECT_DIR/.gitignore"
    fi
  done
}
begin_file() { TEMP_FILE="$(mktemp "$1.tmp.XXXXXX")"; }
finish_file() { chmod "$2" "$TEMP_FILE"; mv -f -- "$TEMP_FILE" "$1"; TEMP_FILE=""; }
copy_script() {
  local name="$1" target="$PROJECT_DIR/$1"
  [[ -f "$SCRIPT_DIR/$name" ]] || fail "Missing bundled file: $name"
  [[ ! -L "$target" ]] || fail "Refusing symlink output: $target"
  if [[ -e "$target" ]] && ! cmp -s "$SCRIPT_DIR/$name" "$target"; then
    yes_no "Replace differing $target?" || return 0
  fi
  if [[ "$SCRIPT_DIR/$name" != "$target" ]]; then cp "$SCRIPT_DIR/$name" "$target"; fi
  chmod 755 "$target"
}
write_example() {
  begin_file "$ENV_EXAMPLE_FILE"
  {
    cat <<'EXAMPLE'
# Generated example: placeholders only. Keep real values in .env.
HETZNER_API_TOKEN="your-hetzner-api-token"
HETZNER_SERVER_TYPE="cx23"
HETZNER_LOCATION="fsn1"
HETZNER_IMAGE="ubuntu-24.04"
SSH_PUBLIC_KEY_PATH="$HOME/.ssh/agentbox_hetzner_ed25519.pub"
# Optional: skip the Tailscale browser approval with your auth key.
# TAILSCALE_AUTH_KEY="your-tailscale-auth-key"
MODEL_PROVIDER="your-provider-id"
MODEL_BASE_URL="https://api.example.com/v1"
MODEL_API_KEY="your-model-api-key"
MODEL_ID="your-provider/your-model"
EXAMPLE
    if [[ "$RUNTIME" == hermes ]]; then
      cat <<'EXAMPLE'
# Hermes requires a bot and numeric user allowlist during setup.
TELEGRAM_BOT_TOKEN="your-telegram-bot-token"
TELEGRAM_ALLOWED_USERS="your-numeric-telegram-user-id"
TELEGRAM_ALLOW_FROM="your-numeric-telegram-user-id"
HERMES_SSH_KEY_PASSPHRASE="your-ssh-key-passphrase"
OPENCLAW_SSH_KEY_PASSPHRASE="your-ssh-key-passphrase"
# Enable only for a trusted Telegram admin who needs named host commands:
# HERMES_HOST_COMMANDS=1
# HERMES_GROUP_WORK_MODEL_API_KEY="your-work-model-api-key"
# HERMES_GROUP_WORK_TELEGRAM_BOT_TOKEN="your-work-bot-token"
# HERMES_GROUP_WORK_TELEGRAM_ALLOWED_USERS="your-numeric-telegram-user-id"
EXAMPLE
    else
      cat <<'EXAMPLE'
# OpenClaw: bot optional; empty allow-from uses pairing when a bot is configured.
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOW_FROM=""
OPENCLAW_SSH_KEY_PASSPHRASE="your-ssh-key-passphrase"
EXAMPLE
    fi
  } > "$TEMP_FILE"
  finish_file "$ENV_EXAMPLE_FILE" 644
}
write_env_values() {
  env_line HETZNER_API_TOKEN "$TOKEN"
  env_line HETZNER_SERVER_TYPE "$SERVER_TYPE"
  env_line HETZNER_LOCATION "$LOCATION"
  env_line HETZNER_IMAGE ubuntu-24.04
  env_line MODEL_PROVIDER "$MODEL_PROVIDER"
  env_line MODEL_BASE_URL "$MODEL_BASE_URL"
  env_line MODEL_API_KEY "$MODEL_API_KEY"
  env_line MODEL_ID "$MODEL_ID"
  env_line TELEGRAM_BOT_TOKEN "$BOT_TOKEN"
  env_line TELEGRAM_ALLOW_FROM "$ALLOW_FROM"
  env_line SSH_PUBLIC_KEY_PATH "$KEY_PATH.pub"
  env_line TAILSCALE_AUTH_KEY "$TS_KEY"
  if [[ "$RUNTIME" == hermes ]]; then
    env_line TELEGRAM_ALLOWED_USERS "$ALLOW_FROM"
    env_line HERMES_SSH_KEY_PASSPHRASE "$PASSPHRASE"
  fi
  env_line OPENCLAW_SSH_KEY_PASSPHRASE "$PASSPHRASE"
}

# The first question always selects the runtime, before replacements or credentials.
while :; do
  ask 'Agent runtime: Hermes or OpenClaw? [Hermes]' optional no hermes
  case "$REPLY" in
    hermes|Hermes|HERMES|1) RUNTIME=hermes; break ;;
    openclaw|OpenClaw|Openclaw|OPENCLAW|2) RUNTIME=openclaw; break ;;
    *) printf 'Choose Hermes or OpenClaw.\n' >&2 ;;
  esac
done
[[ -d "$PROJECT_DIR" ]] || fail "Project directory does not exist: $PROJECT_DIR"
PROJECT_DIR="$(cd -- "$PROJECT_DIR" && pwd -P)"
assert_runtime_directory "$PROJECT_DIR"
output_path "${ENV_FILE:-.env}"; ENV_FILE="$REPLY"
output_path "${ENV_EXAMPLE_FILE:-.env.example}"; ENV_EXAMPLE_FILE="$REPLY"
output_path "${CREDENTIALS_FILE:-credentials.txt}"; CREDENTIALS_FILE="$REPLY"
for path in "$ENV_FILE" "$ENV_EXAMPLE_FILE" "$CREDENTIALS_FILE"; do
  refuse_tracked_path "$path"
done
[[ "$ENV_FILE" != "$ENV_EXAMPLE_FILE" && "$ENV_FILE" != "$CREDENTIALS_FILE" && "$ENV_EXAMPLE_FILE" != "$CREDENTIALS_FILE" ]] || fail 'Output paths must differ'
for path in "$ENV_FILE" "$CREDENTIALS_FILE"; do
  [[ "$path" != *.example* ]] || fail "Secret output cannot be an example: $path"
done
for path in "$ENV_FILE" "$ENV_EXAMPLE_FILE" "$CREDENTIALS_FILE"; do
  case "${path#"$PROJECT_DIR/"}" in
    .git/*|.gitignore|boxes.json|boxes.example.json|*.sh) fail "Reserved output path: $path" ;;
  esac
done
cat <<'TYPES'
Choose a Hetzner box (availability varies by location):
  cx23  Recommended: 2 vCPU / 4 GB RAM, cheap shared x86 (Intel/AMD).
  cax11 2 vCPU / 4 GB RAM, shared ARM (Ampere; NBG1/HEL1 locations).
  cx33  4 vCPU / 8 GB RAM, shared x86, more room for groups/agents.
All listed plans share CPU resources. You can enter any type, including dedicated CCX.
TYPES
ask "Server type [${HETZNER_SERVER_TYPE:-cx23}]" optional no "${HETZNER_SERVER_TYPE:-cx23}"
SERVER_TYPE="$REPLY"
[[ "$SERVER_TYPE" =~ ^[a-z][a-z0-9]+$ ]] || fail 'Invalid server type name'
ask "Location [${HETZNER_LOCATION:-fsn1}] (e.g. fsn1, nbg1, hel1)" optional no "${HETZNER_LOCATION:-fsn1}"
LOCATION="$REPLY"
[[ "$LOCATION" =~ ^[a-z][a-z0-9]+$ ]] || fail 'Invalid location name'
command -v curl >/dev/null || fail 'curl is required for token validation'
command -v jq >/dev/null || fail 'jq is required for server type validation'
printf 'Hetzner token: https://console.hetzner.cloud/ -> Project -> Security -> API Tokens -> Read & Write\n'
ask 'Hetzner API token' required yes; TOKEN="$REPLY"
AUTH_HEADER_FILE="$(mktemp "${TMPDIR:-/tmp}/setup-agent-box.auth.XXXXXX")"
SERVER_TYPES_FILE="$(mktemp "${TMPDIR:-/tmp}/setup-agent-box.server-types.XXXXXX")"
chmod 600 "$AUTH_HEADER_FILE" "$SERVER_TYPES_FILE"
printf 'Authorization: Bearer %s\n' "$TOKEN" > "$AUTH_HEADER_FILE"
if ! curl -fsS --connect-timeout 10 --max-time 30 -H "@$AUTH_HEADER_FILE" \
  https://api.hetzner.cloud/v1/server_types > "$SERVER_TYPES_FILE"; then
  fail 'Hetzner token validation failed; check token and network'
fi
jq -e '.server_types | type == "array"' "$SERVER_TYPES_FILE" >/dev/null 2>&1 || \
  fail 'Hetzner server types response was invalid'
if ! jq -e --arg type "$SERVER_TYPE" --arg location "$LOCATION" \
  'any(.server_types[]?; .name == $type and ((.locations // []) | index($location) != null))' \
  "$SERVER_TYPES_FILE" >/dev/null; then
  available="$(jq -r --arg type "$SERVER_TYPE" \
    '[.server_types[]? | select(.name == $type) | (.locations // [])[]?] | join(", ")' \
    "$SERVER_TYPES_FILE" 2>/dev/null || true)"
  if [[ -n "$available" ]]; then
    fail "Server type $SERVER_TYPE is unavailable in $LOCATION; available: $available; consider: ${available%%,*}"
  fi
  fail "Unknown Hetzner server type: $SERVER_TYPE"
fi
[[ ! -L "$PROJECT_DIR/.gitignore" ]] || fail 'Refusing symlink .gitignore'
touch "$PROJECT_DIR/.gitignore"
ignore_path "$ENV_FILE"
ignore_path "$CREDENTIALS_FILE"
ignore_path "$PROJECT_DIR/boxes.json"
# Re-include the example even when a custom env prefix would otherwise ignore it.
example_relative="${ENV_EXAMPLE_FILE#"$PROJECT_DIR/"}"
if ! grep -qxF "!/$example_relative" "$PROJECT_DIR/.gitignore"; then
  printf '!/%s\n' "$example_relative" >> "$PROJECT_DIR/.gitignore"
fi
if [[ -e "$ENV_FILE" ]]; then
  chmod 600 "$ENV_FILE"
  if ! yes_no "Back up and replace existing $ENV_FILE?"; then
    if yes_no "Write $ENV_EXAMPLE_FILE with safe placeholders anyway?"; then write_example; fi
    exit 0
  fi
fi
if [[ -e "$CREDENTIALS_FILE" ]]; then
  chmod 600 "$CREDENTIALS_FILE"
  yes_no "Back up and replace $CREDENTIALS_FILE (including any VPS handoff)?" || fail 'Existing credentials preserved'
fi
ask 'Model provider id' required no; MODEL_PROVIDER="$REPLY"
ask 'Model API base URL' required no; MODEL_BASE_URL="$REPLY"
while :; do
  ask 'Model API key' required yes; MODEL_API_KEY="$REPLY"
  [[ "${#MODEL_API_KEY}" -ge 20 ]] && break
  printf 'Model API key looks truncated (shorter than 20 characters).\n' >&2
done
ask 'Default model (format: provider/model-id)' required no; MODEL_ID="$REPLY"
if [[ "$RUNTIME" == hermes ]]; then
  ask 'Telegram bot token (from @BotFather)' required yes; BOT_TOKEN="$REPLY"
else
  ask 'Telegram bot token (optional; blank to configure later)' optional yes; BOT_TOKEN="$REPLY"
fi
while :; do
  required=optional
  [[ "$RUNTIME" != hermes ]] || required=required
  ask 'Telegram numeric user allowlist (OpenClaw: blank for pairing)' "$required"; ALLOW_FROM="$REPLY"
  [[ -z "$ALLOW_FROM" || "$ALLOW_FROM" =~ ^[0-9]+([,[:space:]]+[0-9]+)*$ ]] && break
  printf 'Use numeric IDs separated by commas or spaces.\n' >&2
done
ask 'Tailscale auth key (optional; blank for browser login)' optional yes; TS_KEY="$REPLY"
DEFAULT_KEY_PATH="${DEFAULT_KEY_PATH:-}"
if [[ -z "$DEFAULT_KEY_PATH" ]]; then
  DEFAULT_KEY_PATH="$HOME/.ssh/agentbox_hetzner_ed25519"
  if [[ -f "$HOME/.ssh/openclaw_hetzner_passphrase_ed25519" ]]; then
    DEFAULT_KEY_PATH="$HOME/.ssh/openclaw_hetzner_passphrase_ed25519"
  fi
fi
ask "SSH private key path [$DEFAULT_KEY_PATH]" optional no "$DEFAULT_KEY_PATH"
KEY_PATH="${REPLY/#\~/$HOME}"
[[ "$KEY_PATH" == /* ]] || KEY_PATH="$PROJECT_DIR/$KEY_PATH"
[[ "$KEY_PATH" != "$PROJECT_DIR"/* ]] || fail "SSH private key must be outside the project; use a path such as ~/.ssh/agentbox_hetzner_ed25519"
assert_runtime_directory "$(dirname -- "$KEY_PATH")"
if [[ -e "$KEY_PATH" ]]; then
  [[ -f "$KEY_PATH.pub" ]] || fail "Missing public key: $KEY_PATH.pub (recover it with ssh-keygen -y)"
  ask 'SSH key passphrase (blank for none)' optional yes; PASSPHRASE="$REPLY"
else
  key_directory="$(dirname -- "$KEY_PATH")"
  key_directory_existed=0
  [[ -d "$key_directory" ]] && key_directory_existed=1
  mkdir -p -- "$key_directory"
  [[ "$key_directory_existed" -eq 1 ]] || chmod 700 "$key_directory"
  ask 'New SSH key passphrase (blank to generate a strong passphrase)' optional yes
  PASSPHRASE="$REPLY"
  if [[ -z "$PASSPHRASE" ]]; then
    command -v openssl >/dev/null || fail 'openssl is required to generate a passphrase'
    PASSPHRASE="$(openssl rand -base64 32)"
  fi
  ssh-keygen -t ed25519 -a 100 -f "$KEY_PATH" -N "$PASSPHRASE" -C "agentbox-hetzner-$(date +%Y%m%d)"
fi
copy_script "$RUNTIME-hetzner.sh"
copy_script "$RUNTIME-vps.sh"
copy_script agent-box-manage.sh
if [[ ! -e "$PROJECT_DIR/boxes.example.json" ]]; then
  cp "$SCRIPT_DIR/../boxes.example.json" "$PROJECT_DIR/boxes.example.json"
  chmod 644 "$PROJECT_DIR/boxes.example.json"
fi
for path in "$ENV_FILE" "$CREDENTIALS_FILE"; do
  if [[ -e "$path" ]]; then
    backup="$(mktemp "$path.bak.XXXXXX")"
    cp "$path" "$backup"
    chmod 600 "$backup"
  fi
done
begin_file "$ENV_FILE"
{ printf '# %s Hetzner configuration. Local secrets; never commit.\n' "$RUNTIME"; write_env_values; } > "$TEMP_FILE"
finish_file "$ENV_FILE" 600
write_example
begin_file "$CREDENTIALS_FILE"
{
  printf '# Local %s credentials. Never commit or paste into chat.\n' "$RUNTIME"
  printf 'Generated at: %s\n\n[Secrets and configuration]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_env_values
  printf '\nSSH private key: %s\n\n[Install command]\n' "$KEY_PATH"
  printf 'cd %q\nset -a && source %q && set +a\n' "$PROJECT_DIR" "$ENV_FILE"
  printf './%s-hetzner.sh install\n' "$RUNTIME"
  printf '# Type CREATE at the paid-server prompt. Complete any Tailscale browser login.\n'
  printf '\n[VPS handoff - fill only after successful install]\nServer ID=\nServer name=\nPublic IP=\nTailscale IP=\nRoot password=\nSSH command=\n'
  printf '\n[Record non-secret metadata after successful install]\n./agent-box-manage.sh register --runtime %s\n' "$RUNTIME"
} > "$TEMP_FILE"
finish_file "$CREDENTIALS_FILE" 600
bash -n "$ENV_FILE"
bash -n "$ENV_EXAMPLE_FILE"
printf 'Created .env and credentials handoff with mode 600; safe example written.\n'
printf 'Next: cd %q\nset -a && source %q && set +a\n./%s-hetzner.sh install\n' "$PROJECT_DIR" "$ENV_FILE" "$RUNTIME"
printf 'Type CREATE yourself. Pause for the Tailscale browser login URL if shown.\n'
printf 'After install succeeds: ./agent-box-manage.sh register --runtime %s\n' "$RUNTIME"
