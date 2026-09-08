#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PROJECT_DIR="$PWD"
STATE_FILE=""
BOX=""; RUNTIME=""; GROUP=""; AGENT=""
SERVER_ID=""; SERVER_TYPE=""; LOCATION=""; PUBLIC_IP=""; TAILSCALE_IP=""; SSH_KEY=""; CREATED_AT=""
TEMP_FILE=""; LOCK_DIR=""
usage() {
  cat <<'USAGE'
Usage: agent-box-manage.sh COMMAND [--project-dir DIR] [--state FILE] [--box NAME]

Commands:
  boxes          List the local inventory (no network).
  register       Record a successfully installed box; prompts for missing metadata.
  status, doctor, logs, backup, maintenance, refresh-config, lockdown
  serve, serve-off                       OpenClaw only; expose or disable the dashboard over Tailscale.
  add-group --group NAME
  add-agent --agent ID --group NAME     OpenClaw only.
  list                                 OpenClaw remote groups/agents.

Hermes lifecycle commands accept --group NAME (default: default).
OpenClaw lifecycle commands act on the whole box; group selectors are rejected.
The dashboard commands are OpenClaw-only, box-wide, and reject --group/--agent.
For boxes installed from the GitHub raw URL before this change, upload the updated
script first: scp openclaw-vps.sh root@<ts-ip>:/root/openclaw-vps.sh
If exactly one box is recorded, --box can be omitted. State defaults to
PROJECT_DIR/boxes.json. Requires jq and SSH; wrappers live in PROJECT_DIR.
Use a working directory outside skill folders; skill contents stay stateless.

register options (non-secret values only):
  --runtime hermes|openclaw --box NAME --server-id ID --server-type TYPE
  --location LOCATION --public-ip IP --tailscale-ip IP --ssh-key PRIVATE_KEY
  --created-at UTC_TIMESTAMP (default: registration time)
Seeds default Hermes group, or OpenClaw main group + main agent. Existing box
names/server IDs are rejected. For existing inventories, reconcile metadata locally.
No .env is sourced automatically. SSH prompts for passphrases when needed.
Confirmations remain interactive; no --yes or arbitrary remote commands accepted.
USAGE
}
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
assert_runtime_directory() {
  local directory="$1"
  directory="$(cd -- "$directory" && pwd -P)"
  while :; do
    [[ ! -f "$directory/SKILL.md" ]] || fail 'Runtime files must be outside skill folders; choose a separate --project-dir and output paths'
    [[ "$directory" != / ]] || break
    directory="$(dirname -- "$directory")"
  done
}
cleanup() {
  [[ -z "$TEMP_FILE" ]] || rm -f -- "$TEMP_FILE"
  [[ -z "$LOCK_DIR" ]] || rmdir -- "$LOCK_DIR"
}
trap cleanup EXIT
COMMAND="${1:---help}"
[[ $# -eq 0 ]] || shift
case "$COMMAND" in -h|--help|help) usage; exit 0 ;; esac
while (($#)); do
  [[ -n "${2:-}" ]] || fail "$1 requires a value"
  case "$1" in
    --project-dir) PROJECT_DIR="$2" ;;
    --state) STATE_FILE="$2" ;;
    --box) BOX="$2" ;;
    --group) GROUP="$2" ;;
    --agent) AGENT="$2" ;;
    --runtime) RUNTIME="$2" ;;
    --server-id) SERVER_ID="$2" ;;
    --server-type) SERVER_TYPE="$2" ;;
    --location) LOCATION="$2" ;;
    --public-ip) PUBLIC_IP="$2" ;;
    --tailscale-ip) TAILSCALE_IP="$2" ;;
    --ssh-key) SSH_KEY="$2" ;;
    --created-at) CREATED_AT="$2" ;;
    *) fail "Unknown argument: $1" ;;
  esac
  shift 2
done
case "$COMMAND" in
  boxes|register|status|doctor|logs|backup|maintenance|refresh-config|lockdown|serve|serve-off|add-group|add-agent|list) ;;
  *) fail "Unsupported command: $COMMAND" ;;
esac
command -v jq >/dev/null || fail 'jq is required; install it with your system package manager'
[[ -d "$PROJECT_DIR" ]] || fail "Missing project directory: $PROJECT_DIR"
PROJECT_DIR="$(cd -- "$PROJECT_DIR" && pwd -P)"
assert_runtime_directory "$PROJECT_DIR"
STATE_FILE="${STATE_FILE:-$PROJECT_DIR/boxes.json}"
[[ "$STATE_FILE" == /* ]] || STATE_FILE="$PROJECT_DIR/$STATE_FILE"
[[ -d "$(dirname -- "$STATE_FILE")" ]] || fail 'State parent directory must exist'
STATE_FILE="$(cd -- "$(dirname -- "$STATE_FILE")" && pwd -P)/$(basename -- "$STATE_FILE")"
assert_runtime_directory "$(dirname -- "$STATE_FILE")"
[[ "$STATE_FILE" == "$PROJECT_DIR/"* ]] || fail 'State must be inside the project so it can be gitignored'
[[ "$STATE_FILE" == *.json && "$STATE_FILE" != *.example.json && "$STATE_FILE" != "$PROJECT_DIR/.git/"* ]] || fail 'Use a local .json state filename, not an example or git metadata'
[[ ! -L "$STATE_FILE" ]] || fail 'Refusing symlink state file'
refuse_tracked_path() {
  local path="$1" repo_root relative
  command -v git >/dev/null || return 0
  repo_root="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ "$path" == "$repo_root/"* ]] || return 0
  relative="${path#"$repo_root/"}"
  if git -C "$repo_root" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
    fail "Refusing already tracked state target: $path; ignore rules do not protect tracked files"
  fi
}
refuse_tracked_path "$STATE_FILE"

# Reject unknown fields (including password/token fields), malformed routing data,
# duplicate identities, and mismatched runtime paths before dispatch or persistence.
validate_state() {
  jq -e '
    def ident: type == "string" and test("^[a-z][a-z0-9-]{0,31}$");
    def hermes_group: type == "string" and test("^[A-Za-z0-9_-]+$");
    def ipv4: type == "string" and test("^[0-9]+(\\.[0-9]+){3}$") and
      (split(".") | all(.[]; (tonumber >= 0 and tonumber <= 255)));
    def boxvalid:
      (keys == (["name","runtime","server_id","server_type","location","public_ip","tailscale_ip","ssh_key_path","groups","agents","paths","created_at"] | sort)) and
      (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$")) and (.runtime == "hermes" or .runtime == "openclaw") and
      (.server_id | type == "string" and test("^[1-9][0-9]*$")) and
      (.server_type | type == "string" and test("^[a-z][a-z0-9]+$")) and
      (.location | type == "string" and test("^[a-z][a-z0-9]+$")) and
      (.public_ip | ipv4) and (.tailscale_ip | ipv4) and
      (.tailscale_ip | split(".") | .[0] == "100" and (.[1] | tonumber) >= 64 and (.[1] | tonumber) <= 127) and
      (.ssh_key_path | type == "string" and startswith("/") and (test("[\u0000-\u001f]") | not)) and
      (.runtime as $runtime | .groups | type == "array" and length > 0 and all(.[]; if $runtime == "hermes" then hermes_group else ident end) and (length == (unique | length))) and
      (.agents | type == "array") and
      (.groups as $groups | all(.agents[]; (keys == ["group","id"]) and (.id | ident) and (.group as $g | $groups | index($g) != null))) and
      ((.agents | length) == ([.agents[].id] | unique | length)) and
      (if .runtime == "hermes" then .agents == [] else true end) and
      (.paths == {vps_script: ("/root/" + .runtime + "-vps.sh"), state_dir: ("/var/lib/" + .runtime + "-vps")}) and
      (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"));
    (keys == ["boxes","version"]) and .version == 1 and
    (.boxes | type == "array" and all(.[]; boxvalid)) and
    ((.boxes | length) == ([.boxes[].name] | unique | length)) and
    ((.boxes | length) == ([.boxes[].server_id] | unique | length))
  ' "$1" >/dev/null 2>&1 || fail 'Invalid boxes schema or routing metadata; no command dispatched'
}
lock_state() {
  local lock="$STATE_FILE.lock"
  mkdir -- "$lock" 2>/dev/null || fail "State is busy ($lock); remove a stale lock only after verifying no writer is running"
  LOCK_DIR="$lock"
}
ignore_state() {
  local relative="${STATE_FILE#"$PROJECT_DIR/"}" entry
  [[ ! -L "$PROJECT_DIR/.gitignore" ]] || fail 'Refusing symlink .gitignore'
  touch "$PROJECT_DIR/.gitignore"
  relative="${relative//\\/\\\\}"; relative="${relative//\[/\\[}"
  relative="${relative//\*/\\*}"; relative="${relative//\?/\\?}"; relative="${relative// /\\ }"
  for entry in "/$relative" "/$relative.*"; do
    if ! grep -qxF -- "$entry" "$PROJECT_DIR/.gitignore"; then
      printf '%s\n' "$entry" >> "$PROJECT_DIR/.gitignore"
    fi
  done
}
write_state() {
  TEMP_FILE="$(mktemp "$STATE_FILE.tmp.XXXXXX")"
  printf '%s\n' "$STATE" > "$TEMP_FILE"
  validate_state "$TEMP_FILE"
  chmod 600 "$TEMP_FILE"
  mv -f -- "$TEMP_FILE" "$STATE_FILE"
  TEMP_FILE=""
}
prompt_field() {
  local var="$1" label="$2" default="${3:-}" value="${!1}"
  [[ -z "$value" ]] || return 0
  while [[ -z "$value" ]]; do
    printf '%s%s: ' "$label" "${default:+ [$default]}" >&2
    IFS= read -r value || fail 'Input ended; registration cancelled'
    value="${value:-$default}"
  done
  printf -v "$var" '%s' "$value"
}
if [[ "$COMMAND" == register || "$COMMAND" == add-group || "$COMMAND" == add-agent ]]; then
  lock_state
  ignore_state
fi
if [[ -f "$STATE_FILE" ]]; then
  chmod 600 "$STATE_FILE"
  validate_state "$STATE_FILE"
  STATE="$(cat "$STATE_FILE")"
else
  [[ "$COMMAND" == register ]] || fail "No inventory at $STATE_FILE; register a successfully installed box first"
  STATE='{"version":1,"boxes":[]}'
fi
if [[ "$COMMAND" == register ]]; then
  [[ -z "$GROUP$AGENT" ]] || fail 'Register seeds initial groups/agents; reconcile existing inventories separately'
  prompt_field RUNTIME 'Agent runtime: hermes or openclaw'
  case "$RUNTIME" in hermes|openclaw) ;; *) fail 'Runtime must be hermes or openclaw' ;; esac
  prompt_field BOX 'Installed server name (local box name)'
  prompt_field SERVER_ID 'Hetzner server ID from successful install'
  prompt_field SERVER_TYPE 'Installed server type' "${HETZNER_SERVER_TYPE:-cx23}"
  prompt_field LOCATION 'Installed location' "${HETZNER_LOCATION:-fsn1}"
  prompt_field PUBLIC_IP 'Public IPv4 from install handoff'
  prompt_field TAILSCALE_IP 'Tailscale IPv4 from install handoff'
  key_default="${SSH_PUBLIC_KEY_PATH:-}"
  prompt_field SSH_KEY 'Absolute SSH private key path' "${key_default%.pub}"
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  CREATED_AT="${CREATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  [[ -f "$SSH_KEY" ]] || fail "SSH private key not found: $SSH_KEY"
  jq -e --arg name "$BOX" --arg id "$SERVER_ID" '.boxes | all(.[]; .name != $name and .server_id != $id)' <<< "$STATE" >/dev/null || fail 'Box name or server ID already registered; existing state preserved'
  STATE="$(jq --arg name "$BOX" --arg runtime "$RUNTIME" --arg id "$SERVER_ID" \
    --arg type "$SERVER_TYPE" --arg location "$LOCATION" --arg public "$PUBLIC_IP" \
    --arg ts "$TAILSCALE_IP" --arg key "$SSH_KEY" --arg created "$CREATED_AT" '
    .boxes += [{name:$name, runtime:$runtime, server_id:$id, server_type:$type,
      location:$location, public_ip:$public, tailscale_ip:$ts, ssh_key_path:$key,
      groups:(if $runtime == "hermes" then ["default"] else ["main"] end),
      agents:(if $runtime == "hermes" then [] else [{id:"main",group:"main"}] end),
      paths:{vps_script:("/root/"+$runtime+"-vps.sh"),state_dir:("/var/lib/"+$runtime+"-vps")},
      created_at:$created}]
  ' <<< "$STATE")"
  write_state
  printf 'Registered %s in %s (mode 600).\n' "$BOX" "$STATE_FILE"
  exit 0
fi
[[ -z "$RUNTIME$SERVER_ID$SERVER_TYPE$LOCATION$PUBLIC_IP$TAILSCALE_IP$SSH_KEY$CREATED_AT" ]] || fail 'Registration options only apply to register'
if [[ "$COMMAND" == boxes ]]; then
  [[ -z "$GROUP$AGENT$BOX" ]] || fail 'boxes does not accept selectors'
  jq -r '.boxes[] | [.name,.runtime,.tailscale_ip,(.groups|join(","))] | @tsv' <<< "$STATE"
  exit 0
fi
if [[ -z "$BOX" ]]; then
  [[ "$(jq '.boxes | length' <<< "$STATE")" == 1 ]] || fail 'Choose --box NAME; use boxes to list the inventory'
  BOX="$(jq -r '.boxes[0].name' <<< "$STATE")"
fi
RECORD="$(jq -ce --arg name "$BOX" '.boxes[] | select(.name == $name)' <<< "$STATE")" || fail "Unknown box: $BOX"
RUNTIME="$(jq -r .runtime <<< "$RECORD")"
HOST="$(jq -r .tailscale_ip <<< "$RECORD")"
SSH_KEY="$(jq -r .ssh_key_path <<< "$RECORD")"
VPS_SCRIPT="$(jq -r .paths.vps_script <<< "$RECORD")"
[[ -f "$SSH_KEY" ]] || fail "SSH key not found: $SSH_KEY"
if [[ "$RUNTIME" == hermes ]]; then
  [[ -z "$GROUP" || "$GROUP" =~ ^[A-Za-z0-9_-]+$ ]] || fail 'Invalid Hermes group ID'
else
  [[ -z "$GROUP" || "$GROUP" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail 'Invalid OpenClaw group ID'
fi
[[ -z "$AGENT" || "$AGENT" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail 'Invalid agent ID'
[[ "$COMMAND" == add-agent || -z "$AGENT" || "$COMMAND" == serve || "$COMMAND" == serve-off ]] || fail '--agent only applies to add-agent'
case "$COMMAND" in
  add-group) [[ -n "$GROUP" ]] || fail 'add-group requires --group' ;;
  add-agent) [[ "$RUNTIME" == openclaw && -n "$GROUP" && -n "$AGENT" ]] || fail 'add-agent requires OpenClaw, --group and --agent' ;;
  list) [[ "$RUNTIME" == openclaw && -z "$GROUP" ]] || fail 'list is an OpenClaw box-wide command' ;;
  lockdown) [[ -z "$GROUP" ]] || fail 'lockdown applies to the whole box' ;;
  serve|serve-off) [[ "$RUNTIME" == openclaw ]] || fail 'serve commands require an OpenClaw box'; [[ -z "$GROUP$AGENT" ]] || fail 'serve commands are box-wide; omit --group and --agent' ;;
esac
if [[ "$RUNTIME" == openclaw && "$COMMAND" != add-group && "$COMMAND" != add-agent && -n "$GROUP" ]]; then
  fail 'OpenClaw lifecycle commands are box-wide; omit --group'
fi
if [[ "$COMMAND" == add-group || "$COMMAND" == add-agent || ( "$RUNTIME" == hermes && "$COMMAND" != lockdown ) ]]; then
  WRAPPER="$PROJECT_DIR/$RUNTIME-hetzner.sh"
  [[ -x "$WRAPPER" && -f "$SSH_KEY.pub" ]] || fail 'Provisioning wrapper or SSH public key missing; run setup in this project'
  args=("$COMMAND" --host "$HOST" --ssh-key "$SSH_KEY.pub")
  if [[ "$RUNTIME" == hermes ]]; then GROUP="${GROUP:-default}"; fi
  [[ -z "$GROUP" ]] || args+=(--group "$GROUP")
  [[ -z "$AGENT" ]] || args+=(--agent "$AGENT")
  # The selected group must override any unrelated HERMES_GROUP inherited from .env.
  "$WRAPPER" "${args[@]}"
else
  # Fixed command allowlist + validated paths; no user-supplied remote shell snippets.
  printf -v remote '%q %q' "$VPS_SCRIPT" "$COMMAND"
  ssh -tt -o IdentitiesOnly=yes -i "$SSH_KEY" "root@$HOST" "$remote"
fi
# Commit local additions only after a successful remote exit. The VPS remains
# authoritative if a connection drops after a mutation or an out-of-band edit.
if [[ "$COMMAND" == add-group || "$COMMAND" == add-agent ]]; then
  STATE="$(jq --arg box "$BOX" --arg group "$GROUP" --arg agent "$AGENT" '
    (.boxes[] | select(.name == $box)) |=
      (.groups = ((.groups + [$group]) | unique) |
       if $agent != "" then .agents = ([.agents[] | select(.id != $agent)] + [{id:$agent,group:$group}]) else . end)
  ' <<< "$STATE")"
  write_state
fi
