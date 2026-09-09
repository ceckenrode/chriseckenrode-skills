#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="${OPENCLAW_VPS_USER:-openclaw}"
APP_HOME="/home/${APP_USER}"
STATE_DIR="/var/lib/openclaw-vps"
LOG_DIR="/var/log/openclaw-vps"
BACKUP_DIR="${STATE_DIR}/backups"
GROUPS_FILE="${STATE_DIR}/groups.json"
AGENTS_FILE="${STATE_DIR}/agents.json"
NODE_MAJOR="24"
GH_INSTALL_PATH="/usr/local/bin/gh"
MODEL_PROVIDER="${MODEL_PROVIDER:-}"
MODEL_BASE_URL="${MODEL_BASE_URL:-}"
MODEL_API_KEY="${MODEL_API_KEY:-}"
MODEL_ID="${MODEL_ID:-}"
MODEL_CATALOG="${MODEL_CATALOG:-}"
OPENCLAW_AGENT_SKILLS="${OPENCLAW_AGENT_SKILLS:-}"
OPENCLAW_PORT="18789"
TAILSCALE_IFACE="tailscale0"
OPENCLAW_TIMEZONE="${OPENCLAW_TIMEZONE:-}"
DEFAULT_GROUP_ID="main"
DEFAULT_AGENT_ID="${OPENCLAW_INITIAL_AGENT_ID:-main}"
OPENCLAW_INITIAL_AGENT_LABEL="${OPENCLAW_INITIAL_AGENT_LABEL:-}"
INCUS_SSH_BASE_PORT="2222"
INCUS_REMOTE_WORKSPACE_ROOT="/workspace/openclaw-sandboxes"

USER_CONFIG_DIR="${APP_HOME}/.config/openclaw-vps"
USER_ENV_FILE="${USER_CONFIG_DIR}/env"
OPENCLAW_CONFIG_DIR="${APP_HOME}/.openclaw"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_DIR}/openclaw.json"
OPENCODE_CONFIG_DIR="${APP_HOME}/.config/opencode"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
USER_BIN_DIR="${APP_HOME}/.local/bin"
USER_SYSTEMD_DIR="${APP_HOME}/.config/systemd/user"
OPENCLAW_SERVICE="openclaw-gateway.service"
SANDBOX_SSH_KEY="${APP_HOME}/.ssh/openclaw-sandbox_ed25519"
SANDBOX_KNOWN_HOSTS_DIR="${APP_HOME}/.ssh/openclaw-sandbox-known-hosts"
GITHUB_SSH_DIR="${APP_HOME}/.ssh"
GITHUB_SSH_KEY="${GITHUB_SSH_DIR}/github_ed25519"
GITHUB_SSH_PUBLIC_KEY="${GITHUB_SSH_KEY}.pub"
GITHUB_SSH_CONFIG="${GITHUB_SSH_DIR}/config"
GITHUB_KNOWN_HOSTS="${GITHUB_SSH_DIR}/known_hosts"
GITHUB_SSH_MARKER="# openclaw-vps github-bootstrap"
GITHUB_SSH_END_MARKER="# end openclaw-vps github-bootstrap"
GITHUB_TRUSTED_ED25519_FINGERPRINT="SHA256:+DiY3wvvV6TuJJhbpZisF/o8t4U7AqW5"
GITHUB_TRUSTED_RSA_FINGERPRINT="SHA256:nThbg6kXUpJWGlmIJbZL"
HOST_ACTION_SCRIPT="/usr/local/sbin/openclaw-vps-host-action"
SERVE_ENABLED_FILE="${STATE_DIR}/serve.enabled"
TAILSCALE_SERVE_TARGET="http://127.0.0.1:${OPENCLAW_PORT}"
MAINTENANCE_HELPER_PATH="/usr/local/sbin/openclaw-vps-maintenance"

ASSUME_YES=0
KEEP_PUBLIC_SSH=0
REQUEST_LOCKDOWN=0

usage() {
  cat <<'USAGE'
Usage: ./openclaw-vps.sh <command> [options]

Commands:
  install                 Harden the VPS, install Tailscale, Node, Incus, OpenClaw, and OpenCode.
  add-group GROUP         Create a new Incus isolation group for OpenClaw agents.
  add-agent AGENT --group GROUP [--sandbox JSON]
                          Create a new OpenClaw agent bound to a Telegram bot and isolation group.
  list                    List managed isolation groups and agents.
  refresh-config          Regenerate OpenClaw/OpenCode config from managed state and restart OpenClaw.
  github-bootstrap        Interactively configure shared-account GitHub access (no token arguments).
  serve                   Expose the loopback dashboard over tailnet-only Tailscale HTTPS.
  serve-off               Disable the Tailscale dashboard exposure.
  lockdown                Enforce Tailscale-only inbound access with UFW.
  status                  Show system, Tailscale, firewall, OpenClaw, and OpenCode status.
  backup                  Create and verify an OpenClaw backup.
  maintenance             Run VPS, Node, OpenClaw, OpenCode, audit, and backup maintenance.
  logs                    Follow the OpenClaw gateway logs.
  doctor                  Run OpenClaw doctor and security audit as the openclaw user.
  help                    Show this help.

Options:
  --lockdown              After install, prompt for explicit LOCKDOWN confirmation and apply UFW lockdown.
  --keep-public-ssh       Keep public SSH open in UFW lockdown. Not recommended for final state.
  -y, --yes               Skip non-lockdown confirmations. LOCKDOWN still requires the word LOCKDOWN.

Environment overrides:
  TAILSCALE_AUTH_KEY      Optional Tailscale auth key for non-interactive tailnet join.
                          Browser login is the default when this is unset.
  MODEL_PROVIDER          Model provider identifier.
  MODEL_BASE_URL          OpenAI-compatible model API base URL.
  MODEL_API_KEY           Model provider API key. If unset, install prompts after fail2ban is active.
  MODEL_ID                Default model reference.
  MODEL_CATALOG           Optional comma-separated model refs; auto-discovered from the provider catalog endpoint when unset.
  TELEGRAM_BOT_TOKEN      Optional Telegram bot token for OpenClaw native Telegram channel.
  TELEGRAM_ALLOW_FROM     Optional numeric Telegram user ID allowlist.
  OPENCLAW_AGENT_TELEGRAM_BOT_TOKEN
                          Optional Telegram bot token for add-agent.
  OPENCLAW_AGENT_TELEGRAM_ALLOW_FROM
                          Optional numeric Telegram user ID allowlist for add-agent.
  OPENCLAW_AGENT_SANDBOX  Explicit JSON sandbox policy for add-agent; otherwise inherit an unambiguous existing policy.
  OPENCLAW_AGENT_SKILLS   Optional comma-separated skill allowlist for every managed agent.
                          Leave unset to let OpenClaw expose all eligible skills.
  OPENCLAW_TIMEZONE       IANA timezone for host, sandbox, and OpenClaw prompts. Default: existing managed env, host timezone, then UTC.

Final intended firewall posture:
  - UFW default deny incoming.
  - UFW default allow outgoing.
  - All inbound traffic allowed on tailscale0.
  - No public SSH unless --keep-public-ssh is explicitly used.
  - OpenClaw gateway binds to loopback only.
  - New installations use persistent host workspaces with sandbox off; existing agents retain their policy.
USAGE
}

log() {
  printf '[openclaw-vps] %s\n' "$*"
}

warn() {
  printf '[openclaw-vps] warning: %s\n' "$*" >&2
}

fail() {
  printf '[openclaw-vps] error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    fail "this command must run as root"
  fi
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  local answer=""
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

shell_quote() {
  printf '%q' "$1"
}

resolve_openclaw_timezone() {
  if [[ -n "$OPENCLAW_TIMEZONE" ]]; then
    return 0
  fi

  local persisted_timezone=""
  if [[ -r "$USER_ENV_FILE" ]]; then
    persisted_timezone="$(bash -c 'set -a; . "$1"; set +a; printf "%s" "${OPENCLAW_TIMEZONE:-${TZ:-}}"' bash "$USER_ENV_FILE")"
  fi
  if [[ -n "$persisted_timezone" ]]; then
    OPENCLAW_TIMEZONE="$persisted_timezone"
    return 0
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    OPENCLAW_TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
  fi
  OPENCLAW_TIMEZONE="${OPENCLAW_TIMEZONE:-UTC}"
}

validate_managed_id() {
  local id="$1"
  [[ "$id" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || fail "invalid id '${id}'; use lowercase letters, numbers, and hyphens, starting with a letter"
}

require_initial_agent_identity() {
  [[ -n "${OPENCLAW_INITIAL_AGENT_ID:-}" ]] || \
    fail 'OPENCLAW_INITIAL_AGENT_ID is required for a fresh OpenClaw install'
  validate_managed_id "$OPENCLAW_INITIAL_AGENT_ID"
  DEFAULT_AGENT_ID="$OPENCLAW_INITIAL_AGENT_ID"
  OPENCLAW_INITIAL_AGENT_LABEL="${OPENCLAW_INITIAL_AGENT_LABEL:-$OPENCLAW_INITIAL_AGENT_ID}"
  OPENCLAW_WORKSPACE="$(new_agent_workspace "$DEFAULT_AGENT_ID")"
}

refuse_existing_managed_state() {
  [[ ! -e "$STATE_DIR" ]] || \
    fail "existing managed OpenClaw state detected at $STATE_DIR; inspect it and use management commands instead of install"
}

ensure_state_files() {
  install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$STATE_DIR" "$BACKUP_DIR"
  if [[ ! -f "$GROUPS_FILE" ]]; then
    printf '{"groups":[]}\n' >"$GROUPS_FILE"
  fi
  if [[ ! -f "$AGENTS_FILE" ]]; then
    printf '{"agents":[]}\n' >"$AGENTS_FILE"
  fi
  chown "$APP_USER:$APP_USER" "$GROUPS_FILE" "$AGENTS_FILE"
  chmod 0640 "$GROUPS_FILE" "$AGENTS_FILE"
}

group_container_name() {
  local group_id="$1"
  local container="openclaw-sandbox-${group_id}"
  printf '%s' "$container"
}

group_host_workspace() {
  local group_id="$1"
  printf '%s/sandbox-workspace-%s' "$APP_HOME" "$group_id"
}

group_known_hosts_file() {
  local group_id="$1"
  printf '%s/%s_known_hosts' "$SANDBOX_KNOWN_HOSTS_DIR" "$group_id"
}

new_agent_workspace() {
  validate_managed_id "$1"
  printf '%s/workspace-%s' "$APP_HOME" "$1"
}

# Read-only preflight. Output is a projection, never a rewrite of legacy state.
# Python's realpath also resolves symlinks in parents of paths not yet created.
resolve_agent_state() {
  python3 - "$AGENTS_FILE" "$OPENCLAW_CONFIG_FILE" "$APP_HOME" "${1:-}" "${OPENCLAW_AGENT_SANDBOX:-}" <<'PY'
import copy
import json
import os
import re
import sys

state_file, config_file, home, new_id, explicit = sys.argv[1:]

def reject(message):
    raise ValueError(message)

def merge(base, override):
    result = copy.deepcopy(base)
    for key, value in override.items():
        result[key] = merge(result[key], value) if isinstance(result.get(key), dict) and isinstance(value, dict) else copy.deepcopy(value)
    return result

def policy(value, agent, partial=False):
    prefix = 'invalid sandbox policy for agent ' + agent + ': '
    if not isinstance(value, dict):
        reject(prefix + 'must be object')
    if (not partial or 'mode' in value) and value.get('mode') not in ('off', 'all', 'non-main'):
        reject(prefix + 'unresolved or unknown mode; select an explicit sandbox policy')
    if 'backend' in value and value['backend'] not in ('ssh', 'docker'):
        reject(prefix + 'unknown backend')
    for field in ('ssh', 'docker', 'browser', 'containers'):
        if field in value and not isinstance(value[field], dict):
            reject(prefix + field + ' must be object')
    for field, allowed in (('scope', ('session', 'agent', 'shared')), ('workspaceAccess', ('none', 'ro', 'rw'))):
        if field in value and value[field] not in allowed:
            reject(prefix + 'unknown ' + field)
    if 'enabled' in value.get('browser', {}) and not isinstance(value['browser']['enabled'], bool):
        reject(prefix + 'browser.enabled must be boolean')
    for field in ('target', 'identityFile', 'knownHostsFile', 'workspaceRoot'):
        if field in value.get('ssh', {}) and (not isinstance(value['ssh'][field], str) or not value['ssh'][field]):
            reject(prefix + 'ssh.' + field + ' must be nonempty string')
    for field in ('strictHostKeyChecking', 'updateHostKeys'):
        if field in value.get('ssh', {}) and not isinstance(value['ssh'][field], bool):
            reject(prefix + 'ssh.' + field + ' must be boolean')
    if not partial and value.get('mode') != 'off' and value.get('backend') == 'ssh' and not value.get('ssh', {}).get('target'):
        reject(prefix + 'SSH target is unresolved')
    return value

def workspace(agent, seen):
    name, path = agent['id'], agent.get('workspace')
    if not isinstance(path, str) or not os.path.isabs(path) or any(ord(c) < 32 for c in path) or os.path.realpath(path) == '/':
        reject('invalid workspace for agent ' + name + ': expected absolute non-root path')
    canonical = os.path.realpath(path)
    if os.path.exists(path) and not os.path.isdir(path):
        reject('invalid workspace for agent ' + name + ': not a directory')
    if canonical in seen:
        reject('duplicate workspace for agents ' + seen[canonical] + ' and ' + name + ': ' + path)
    seen[canonical] = name
    candidates = [os.path.join(home, 'workspace-' + name), os.path.join(home, '.openclaw', 'workspace-' + name), os.path.join(home, 'workspace'), os.path.join(home, '.openclaw', 'workspace')]
    for candidate in candidates:
        if os.path.lexists(candidate) and os.path.realpath(candidate) != canonical:
            reject('duplicate workspace for agent ' + name + ': recorded ' + path + '; conflicting ' + candidate + ' (preserved; reconcile explicitly)')

try:
    with open(state_file) as stream:
        state = json.load(stream)
    if not isinstance(state, dict) or not isinstance(state.get('agents'), list):
        reject('invalid agents.json: agents must be array')
    try:
        with open(config_file) as stream:
            current = json.load(stream)
        if not isinstance(current, dict):
            current = {}
    except (OSError, ValueError):
        current = {}
    config_agents = current.get('agents', {})
    seen, ids = {}, set()
    for agent in state['agents']:
        name = agent.get('id') if isinstance(agent, dict) else None
        if not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,31}', name) or name in ids:
            reject('invalid or duplicate managed agent id')
        ids.add(name)
        workspace(agent, seen)
        for field, kind, label in (('subagents', dict, 'object'), ('skills', list, 'array'), ('contextInjection', str, 'string'), ('bootstrapMaxChars', (int, float), 'number'), ('bootstrapTotalMaxChars', (int, float), 'number'), ('tools', dict, 'object'), ('heartbeat', dict, 'object')):
            if field in agent and (not isinstance(agent[field], kind) or (label == 'number' and isinstance(agent[field], bool))):
                reject('invalid agents.json: agent "' + name + '" field "' + field + '" must be ' + label)
            if field == 'skills' and any(not isinstance(v, str) for v in agent.get(field, [])):
                reject('invalid agents.json: agent "' + name + '" field "skills" must be array of strings')
        if 'sandbox' in agent:
            agent['sandbox'] = policy(agent['sandbox'], name)
            continue
        if not isinstance(config_agents, dict):
            reject('unresolved sandbox policy for agent ' + name)
        matches = []
        for shape in ('list', 'entries'):
            entries = config_agents.get(shape, [])
            if isinstance(entries, dict):
                entries = [dict(value, id=key) for key, value in entries.items() if isinstance(value, dict)]
            if not isinstance(entries, list):
                reject('invalid sandbox current-config agent shape')
            matches.extend(entry for entry in entries if isinstance(entry, dict) and entry.get('id') == name)
        if not matches:
            reject('unresolved sandbox policy for agent ' + name + '; matching current config required')
        defaults = config_agents.get('defaults', {})
        base = defaults.get('sandbox', {}) if isinstance(defaults, dict) else None
        effective = []
        for entry in matches:
            inherited = policy(base, name, partial=True)
            override = policy(entry.get('sandbox', {}), name, partial=True)
            effective.append(policy(merge(inherited, override), name))
        if any(p != effective[0] for p in effective):
            reject('conflicting sandbox policies for agent ' + name)
        agent['sandbox'] = effective[0]
    if new_id:
        if not re.fullmatch(r'[a-z][a-z0-9-]{0,31}', new_id) or new_id in ids:
            reject('invalid or existing new agent id: ' + new_id)
        workspace({'id': new_id, 'workspace': os.path.join(home, 'workspace-' + new_id)}, seen)
        if explicit:
            chosen = policy(json.loads(explicit), new_id)
        elif not state['agents']:
            if os.path.exists(config_file):
                defaults = config_agents.get('defaults', {}) if isinstance(config_agents, dict) else {}
                chosen = policy(defaults.get('sandbox'), new_id)
            else:
                chosen = {'mode': 'off'}
        else:
            choices = [agent['sandbox'] for agent in state['agents']]
            if any(p != choices[0] for p in choices):
                reject('mixed existing policies; select an explicit sandbox policy with --sandbox JSON or OPENCLAW_AGENT_SANDBOX')
            chosen = choices[0]
        print(json.dumps(chosen))
    else:
        print(json.dumps(state))
except (OSError, ValueError, TypeError, KeyError) as error:
    print('[openclaw-vps] error: ' + str(error), file=sys.stderr)
    sys.exit(1)
PY
}

agent_workspace() {
  local resolved
  resolved="$(resolve_agent_state)" || return 1
  jq -er --arg id "$1" '.agents[] | select(.id == $id) | .workspace' <<<"$resolved"
}

agent_dir() {
  local agent_id="$1"
  printf '%s/.openclaw/agents/%s/agent' "$APP_HOME" "$agent_id"
}

bundled_skills_dir() {
  printf '%s/.local/lib/node_modules/openclaw/skills' "$APP_HOME"
}

managed_skill_source_dirs() {
  printf '%s\n' \
    "$APP_HOME/.openclaw/plugin-skills" \
    "$APP_HOME/.openclaw/skills" \
    "$APP_HOME/.agents/skills" \
    "$(bundled_skills_dir)"
}

sync_agent_workspace_skills() {
  local agent_id="$1"
  local workspace skills_source skill_path skill_name target marker
  workspace="$(agent_workspace "$agent_id")" || return 1
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$workspace/skills"
  while IFS= read -r skills_source; do
    [[ -d "$skills_source" ]] || continue
    for skill_path in "$skills_source"/*; do
      [[ -d "$skill_path" && -f "$skill_path/SKILL.md" ]] || continue
      skill_name="${skill_path##*/}"
      target="$workspace/skills/$skill_name"
      marker="$target/.openclaw-vps-managed-skill"
      if [[ -L "$target" ]]; then
        rm -f "$target"
      elif [[ -e "$target" && ! -f "$marker" ]]; then
        if [[ ! -f "$target/SKILL.md" ]] || ! cmp -s "$skill_path/SKILL.md" "$target/SKILL.md"; then
          continue
        fi
      fi
      rm -rf "$target"
      cp -aL "$skill_path" "$target"
      touch "$marker"
      chown -R "$APP_USER:$APP_USER" "$target"
    done
  done < <(managed_skill_source_dirs)
}

prune_missing_managed_workspace_skills() {
  local agent_id="$1"
  local workspace managed_skill skill_name found skills_source
  workspace="$(agent_workspace "$agent_id")" || return 1
  [[ -d "$workspace/skills" ]] || return 0
  for managed_skill in "$workspace/skills"/*; do
    [[ -d "$managed_skill" && -f "$managed_skill/.openclaw-vps-managed-skill" ]] || continue
    skill_name="${managed_skill##*/}"
    found=0
    while IFS= read -r skills_source; do
      if [[ -f "$skills_source/$skill_name/SKILL.md" ]]; then
        found=1
        break
      fi
    done < <(managed_skill_source_dirs)
    if [[ "$found" == "0" ]]; then
      rm -rf "$managed_skill"
    fi
  done
}

sync_all_agent_workspace_skills() {
  resolve_agent_state >/dev/null || return 1
  while IFS= read -r agent_id; do
    [[ -n "$agent_id" ]] || continue
    sync_agent_workspace_skills "$agent_id"
    prune_missing_managed_workspace_skills "$agent_id"
  done < <(jq -r '.agents[]?.id' "$AGENTS_FILE")
}

agent_env_var() {
  local agent_id="$1"
  printf 'TELEGRAM_BOT_TOKEN_%s' "$(printf '%s' "$agent_id" | tr '[:lower:]-' '[:upper:]_')"
}

group_exists() {
  local group_id="$1"
  ensure_state_files
  jq -e --arg id "$group_id" '.groups[]? | select(.id == $id)' "$GROUPS_FILE" >/dev/null
}

agent_exists() {
  local agent_id="$1"
  ensure_state_files
  jq -e --arg id "$agent_id" '.agents[]? | select(.id == $id)' "$AGENTS_FILE" >/dev/null
}

next_group_port() {
  ensure_state_files
  local max_port
  max_port="$(jq -r --argjson base "$INCUS_SSH_BASE_PORT" '[.groups[]?.sshPort] | max // ($base - 1)' "$GROUPS_FILE")"
  local port="$((max_port + 1))"
  while port_is_in_use "$port"; do
    port="$((port + 1))"
  done
  printf '%s' "$port"
}

port_is_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":${port} " && return 0
  fi
  return 1
}

read_group_port() {
  local group_id="$1"
  jq -r --arg id "$group_id" '.groups[] | select(.id == $id) | .sshPort' "$GROUPS_FILE"
}

read_group_container() {
  local group_id="$1"
  jq -r --arg id "$group_id" '.groups[] | select(.id == $id) | .container' "$GROUPS_FILE"
}

write_group_record() {
  local group_id="$1"
  local container="$2"
  local port="$3"
  local host_workspace="$4"
  ensure_state_files
  local tmp
  tmp="$(mktemp "${STATE_DIR}/groups.XXXXXX")"
  jq \
    --arg id "$group_id" \
    --arg container "$container" \
    --argjson sshPort "$port" \
    --arg hostWorkspace "$host_workspace" \
    --arg remoteWorkspaceRoot "$INCUS_REMOTE_WORKSPACE_ROOT" \
    'del(.groups[]? | select(.id == $id)) | .groups += [{id:$id, container:$container, sshPort:$sshPort, hostWorkspace:$hostWorkspace, remoteWorkspaceRoot:$remoteWorkspaceRoot}] | .groups |= sort_by(.id)' \
    "$GROUPS_FILE" >"$tmp"
  mv "$tmp" "$GROUPS_FILE"
  chown "$APP_USER:$APP_USER" "$GROUPS_FILE"
  chmod 0640 "$GROUPS_FILE"
}

normalize_telegram_allow_from() {
  local value="$1"
  if [[ -z "$value" ]]; then
    return 0
  fi
  if [[ "$value" == tg:* ]]; then
    printf '%s' "$value"
  else
    printf 'tg:%s' "$value"
  fi
}

telegram_owner_allow_from() {
  local value="$1"
  if [[ -z "$value" ]]; then
    return 0
  fi
  value="${value#tg:}"
  printf 'telegram:%s' "$value"
}

write_agent_record() {
  local agent_id="$1"
  local group_id="$2"
  local token_env="$3"
  local telegram_allow_from="$4"
  local agent_label="${5:-$agent_id}"
  local is_default="${6:-false}"
  local tmp workspace agent_state allow_value owner_value sandbox_policy
  sandbox_policy="$(resolve_agent_state "$agent_id")" || return 1
  workspace="$(new_agent_workspace "$agent_id")"
  agent_state="$(agent_dir "$agent_id")"
  allow_value="$(normalize_telegram_allow_from "$telegram_allow_from")"
  owner_value="$(telegram_owner_allow_from "$telegram_allow_from")"
  tmp="$(mktemp "${STATE_DIR}/agents.XXXXXX")"
  jq \
    --arg id "$agent_id" \
    --arg group "$group_id" \
    --arg workspace "$workspace" \
    --arg agentDir "$agent_state" \
    --arg telegramAccount "$agent_id" \
    --arg telegramTokenEnv "$token_env" \
    --arg allowFrom "$allow_value" \
    --arg ownerAllowFrom "$owner_value" \
    --arg label "$agent_label" \
    --argjson isDefault "$is_default" \
    --argjson sandbox "$sandbox_policy" \
    'del(.agents[]? | select(.id == $id)) | .agents += [{id:$id, group:$group, workspace:$workspace, agentDir:$agentDir, default:$isDefault, label:$label, sandbox:$sandbox, telegramAccount:$telegramAccount, telegramTokenEnv:$telegramTokenEnv, telegramAllowFrom:$allowFrom, ownerAllowFrom:$ownerAllowFrom}] | .agents |= sort_by(.id)' \
    "$AGENTS_FILE" >"$tmp"
  mv "$tmp" "$AGENTS_FILE"
  chown "$APP_USER:$APP_USER" "$AGENTS_FILE"
  chmod 0640 "$AGENTS_FILE"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$workspace" "$agent_state"
}

set_user_env_value() {
  local key="$1"
  local value="$2"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$USER_CONFIG_DIR"
  touch "$USER_ENV_FILE"
  chown "$APP_USER:$APP_USER" "$USER_ENV_FILE"
  chmod 0600 "$USER_ENV_FILE"
  local tmp
  tmp="$(mktemp "${USER_CONFIG_DIR}/env.XXXXXX")"
  awk -v key="$key" 'BEGIN { prefix = key "=" } index($0, prefix) != 1 { print }' "$USER_ENV_FILE" >"$tmp"
  printf '%s=%s\n' "$key" "$(shell_quote "$value")" >>"$tmp"
  mv "$tmp" "$USER_ENV_FILE"
  chown "$APP_USER:$APP_USER" "$USER_ENV_FILE"
  chmod 0600 "$USER_ENV_FILE"
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

apt_install_hardening_first() {
  log "installing baseline hardening packages before credential prompts"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    fail2ban \
    git \
    gnupg \
    jq \
    lsb-release \
    openssh-server \
    sudo \
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
  ls -ld /run /run/sshd /var/run /var/run/sshd >&2 || true
  ensure_sshd_runtime_dir
  /usr/sbin/sshd -t
}

configure_ssh_hardening() {
  log "hardening SSH before credential prompts"
  install -d -m 0755 /etc/ssh/sshd_config.d
  ensure_sshd_runtime_dir
  cat >/etc/ssh/sshd_config.d/99-openclaw-vps.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
EOF
  if validate_ssh_config; then
    restart_ssh_service
  else
    fail "sshd config validation failed after hardening changes"
  fi
}

configure_fail2ban() {
  log "enabling fail2ban before credential prompts"
  install -d -m 0755 /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/openclaw-vps-sshd.conf <<'EOF'
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
  resolve_openclaw_timezone
  log "configuring host timezone: ${OPENCLAW_TIMEZONE}"
  timedatectl set-timezone "$OPENCLAW_TIMEZONE"
}

ensure_app_user() {
  log "ensuring ${APP_USER} user exists"
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$APP_USER"
  fi
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$APP_HOME"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$USER_CONFIG_DIR" "$OPENCLAW_CONFIG_DIR" "$OPENCODE_CONFIG_DIR" "$USER_SYSTEMD_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "${APP_HOME}/.local"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$USER_BIN_DIR" "$SANDBOX_KNOWN_HOSTS_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$STATE_DIR" "$BACKUP_DIR"
  ensure_state_files
  install -d -m 0755 "$LOG_DIR"
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

install_node() {
  log "installing Node.js ${NODE_MAJOR}.x from NodeSource"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || printf '0')"
    if [[ "$major" == "$NODE_MAJOR" ]]; then
      log "Node.js ${NODE_MAJOR}.x already installed"
      return 0
    fi
  fi
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
  bash /tmp/nodesource_setup.sh
  rm -f /tmp/nodesource_setup.sh
  apt-get install -y nodejs
  node --version
  npm --version
}

ensure_root_subids_for_incus() {
  touch /etc/subuid /etc/subgid
  chmod 0644 /etc/subuid /etc/subgid
  if ! grep -q '^root:' /etc/subuid; then
    printf 'root:1000000:1000000000\n' >>/etc/subuid
  fi
  if ! grep -q '^root:' /etc/subgid; then
    printf 'root:1000000:1000000000\n' >>/etc/subgid
  fi
}

install_incus() {
  log "installing Incus container runtime"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y incus uidmap dnsmasq-base
  ensure_root_subids_for_incus
  systemctl enable --now incus.service >/dev/null 2>&1 || systemctl enable --now incus.socket >/dev/null 2>&1 || true
  need_command incus
}

initialize_incus() {
  log "initializing Incus for local unprivileged containers"
  if incus storage show default >/dev/null 2>&1 && incus network show incusbr0 >/dev/null 2>&1; then
    log "Incus already initialized"
    return 0
  fi

  incus admin init --preseed <<'EOF'
config:
  images.auto_update_interval: "6"
storage_pools:
- name: default
  driver: dir
networks:
- name: incusbr0
  type: bridge
  config:
    ipv4.address: auto
    ipv6.address: none
profiles:
- name: default
  devices:
    root:
      path: /
      pool: default
      type: disk
    eth0:
      name: eth0
      network: incusbr0
      type: nic
EOF
}

incus_exec_bash() {
  local group_id="$1"
  local command_text="$2"
  local container
  container="$(group_container_name "$group_id")"
  incus exec "$container" -- bash -lc "$command_text"
}

ensure_incus_container_running() {
  local group_id="$1"
  local container
  container="$(group_container_name "$group_id")"
  log "ensuring Incus sandbox container exists for group ${group_id}"
  if ! incus info "$container" >/dev/null 2>&1; then
    incus launch images:ubuntu/24.04 "$container" \
      -c security.idmap.isolated=true
  fi
  incus start "$container" >/dev/null 2>&1 || true
  local attempt
  for attempt in {1..60}; do
    if incus exec "$container" -- true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  fail "Incus sandbox container ${container} did not become ready"
}

ensure_incus_workspace_mount() {
  local group_id="$1"
  local container host_workspace
  container="$(group_container_name "$group_id")"
  host_workspace="$(group_host_workspace "$group_id")"
  log "mounting persistent sandbox workspace for group ${group_id}"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$host_workspace"
  if ! incus config device show "$container" | grep -q '^workspace:'; then
    incus config device add "$container" workspace disk source="$host_workspace" path=/workspace shift=true
  fi
}

configure_incus_container_os() {
  resolve_openclaw_timezone
  local group_id="$1"
  local container
  container="$(group_container_name "$group_id")"
  log "installing sandbox container packages and timezone for group ${group_id}"
  incus_exec_bash "$group_id" "export DEBIAN_FRONTEND=noninteractive; for attempt in {1..30}; do apt-get update && break; sleep 2; done; apt-get install -y build-essential ca-certificates curl file git gnupg jq openssh-client openssh-server python3 python3-pip python3-venv pipx ripgrep sudo tar tmux tzdata unzip zip; curl -fsSL 'https://deb.nodesource.com/setup_${NODE_MAJOR}.x' -o /tmp/nodesource_setup.sh; bash /tmp/nodesource_setup.sh; rm -f /tmp/nodesource_setup.sh; apt-get install -y nodejs; systemctl enable --now ssh.service || systemctl enable --now ssh || true"
  if ! incus exec "$container" -- id -u "$APP_USER" >/dev/null 2>&1; then
    incus exec "$container" -- useradd --create-home --shell /bin/bash "$APP_USER"
  fi
  install_sandbox_uv "$group_id"
  verify_sandbox_runtime_versions "$group_id"
  incus_exec_bash "$group_id" "install -d -o '$APP_USER' -g '$APP_USER' -m 0755 /workspace '$INCUS_REMOTE_WORKSPACE_ROOT'"
  incus exec "$container" -- timedatectl set-timezone "$OPENCLAW_TIMEZONE"
  incus exec "$container" -- timedatectl
}

install_sandbox_uv() {
  local group_id="$1"
  log "installing uv for sandbox group ${group_id}"
  incus_exec_bash "$group_id" "sudo -Hiu '$APP_USER' bash -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; curl -LsSf https://astral.sh/uv/install.sh | sh; uv --version'"
}

verify_sandbox_runtime_versions() {
  local group_id="$1"
  log "verifying sandbox Node.js, npm, Python, pip, venv, and uv for group ${group_id}"
  incus_exec_bash "$group_id" "node_major=\$(node -p 'process.versions.node.split(\".\")[0]' 2>/dev/null || printf 0); if [ \"\$node_major\" -lt '${NODE_MAJOR}' ]; then echo 'node major too old: expected >= ${NODE_MAJOR}, got' \"\$node_major\" >&2; exit 1; fi; npm --version >/dev/null; python_minor=\$(python3 - <<'PY'
import sys
print(f'{sys.version_info.major}.{sys.version_info.minor}')
PY
); python3 - <<'PY'
import sys
raise SystemExit(0 if sys.version_info >= (3, 12) else 1)
PY
python3 -m pip --version >/dev/null; tmp=\$(mktemp -d); python3 -m venv \"\$tmp/venv\"; rm -rf \"\$tmp\"; sudo -Hiu '$APP_USER' bash -lc 'export PATH=\"\$HOME/.local/bin:\$PATH\"; uv --version >/dev/null'"
}

ensure_incus_ssh_proxy() {
  local group_id="$1"
  local container port
  container="$(group_container_name "$group_id")"
  port="$(read_group_port "$group_id")"
  log "exposing sandbox SSH on host loopback only for group ${group_id}"
  if ! incus config device show "$container" | grep -q '^ssh-proxy:'; then
    incus config device add "$container" ssh-proxy proxy listen=tcp:127.0.0.1:${port} connect=tcp:127.0.0.1:22
  fi
}

configure_sandbox_ssh_access() {
  local group_id="$1"
  local port known_hosts
  port="$(read_group_port "$group_id")"
  known_hosts="$(group_known_hosts_file "$group_id")"
  log "configuring strict SSH access into Incus sandbox for group ${group_id}"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "${APP_HOME}/.ssh" "$SANDBOX_KNOWN_HOSTS_DIR"
  if [[ ! -f "$SANDBOX_SSH_KEY" ]]; then
    run_as_app_user "ssh-keygen -t ed25519 -N '' -f '${SANDBOX_SSH_KEY}' -C 'openclaw-incus-sandbox'"
  fi

  local pub_key
  pub_key="$(cat "${SANDBOX_SSH_KEY}.pub")"
  incus_exec_bash "$group_id" "install -d -o '$APP_USER' -g '$APP_USER' -m 0700 '/home/$APP_USER/.ssh'; touch '/home/$APP_USER/.ssh/authorized_keys'; chown '$APP_USER:$APP_USER' '/home/$APP_USER/.ssh/authorized_keys'; chmod 0600 '/home/$APP_USER/.ssh/authorized_keys'; grep -qxF $(shell_quote "$pub_key") '/home/$APP_USER/.ssh/authorized_keys' || printf '%s\n' $(shell_quote "$pub_key") >> '/home/$APP_USER/.ssh/authorized_keys'"

  rm -f "$known_hosts"
  local attempt
  for attempt in {1..30}; do
    if ssh-keyscan -p "$port" 127.0.0.1 >"$known_hosts" 2>/dev/null; then
      break
    fi
    sleep 2
  done
  [[ -s "$known_hosts" ]] || fail "could not read sandbox SSH host key from 127.0.0.1:${port}"
  chown "$APP_USER:$APP_USER" "$known_hosts"
  chmod 0600 "$known_hosts"
  run_as_app_user "ssh -i '${SANDBOX_SSH_KEY}' -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='${known_hosts}' -p '${port}' '${APP_USER}@127.0.0.1' 'pwd' >/dev/null"
}

configure_incus_sandbox() {
  local group_id="$1"
  initialize_incus
  ensure_incus_container_running "$group_id"
  ensure_incus_workspace_mount "$group_id"
  configure_incus_container_os "$group_id"
  ensure_incus_ssh_proxy "$group_id"
  configure_sandbox_ssh_access "$group_id"
}

ensure_group() {
  local group_id="$1"
  validate_managed_id "$group_id"
  ensure_state_files
  if group_exists "$group_id"; then
    log "isolation group ${group_id} already exists"
    configure_incus_sandbox "$group_id"
    return 0
  fi

  local container port host_workspace
  container="$(group_container_name "$group_id")"
  port="$(next_group_port)"
  host_workspace="$(group_host_workspace "$group_id")"
  write_group_record "$group_id" "$container" "$port" "$host_workspace"
  configure_incus_sandbox "$group_id"
  log "created isolation group ${group_id}: ${container} on 127.0.0.1:${port}"
}

ensure_agent() {
  local agent_id="$1"
  local group_id="$2"
  local telegram_token="$3"
  local telegram_allow_from="$4"
  local agent_label="${5:-$agent_id}"
  local is_default="${6:-false}"
  validate_managed_id "$agent_id"
  validate_managed_id "$group_id"
  resolve_agent_state "$agent_id" >/dev/null || return 1
  group_exists "$group_id" || fail "isolation group not found: ${group_id}"
  if agent_exists "$agent_id"; then
    fail "agent already exists: ${agent_id}"
  fi
  local token_env=""
  if [[ -n "$telegram_token" ]]; then
    token_env="$(agent_env_var "$agent_id")"
    set_user_env_value "$token_env" "$telegram_token"
  fi
  write_agent_record "$agent_id" "$group_id" "$token_env" "$telegram_allow_from" "$agent_label" "$is_default"
  sync_agent_workspace_skills "$agent_id"
  log "created agent ${agent_id} in isolation group ${group_id}"
}

run_as_app_user() {
  local command_text="$1"
  sudo -Hiu "$APP_USER" bash -lc "export PATH='${USER_BIN_DIR}:/usr/local/bin:/usr/bin:/bin'; ${command_text}"
}

# Use this only for commands whose arguments may contain operator-controlled
# values. In particular, git config values must never become shell source text.
run_as_app_user_literal() {
  local executable="$1"
  shift
  sudo -Hiu "$APP_USER" -- "$executable" "$@"
}

ensure_git_identity() {
  local value

  if ! value="$(run_as_app_user_literal git config --global --get user.name 2>/dev/null)" || [[ -z "$value" ]]; then
    IFS= read -r -p 'Git user.name: ' value || fail 'could not read git user.name'
    [[ -n "$value" ]] || fail 'git user.name cannot be empty'
    run_as_app_user_literal git config --global user.name "$value" || fail 'could not set git user.name'
  fi

  if ! value="$(run_as_app_user_literal git config --global --get user.email 2>/dev/null)" || [[ -z "$value" ]]; then
    IFS= read -r -p 'Git user.email: ' value || fail 'could not read git user.email'
    [[ -n "$value" ]] || fail 'git user.email cannot be empty'
    run_as_app_user_literal git config --global user.email "$value" || fail 'could not set git user.email'
  fi

  if ! value="$(run_as_app_user_literal git config --global --get init.defaultBranch 2>/dev/null)" || [[ -z "$value" ]]; then
    IFS= read -r -p 'Git default branch [main]: ' value || fail 'could not read git default branch'
    value="${value:-main}"
    run_as_app_user_literal git config --global init.defaultBranch "$value" || fail 'could not set git default branch'
  fi
}

refuse_symlink_path() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

path = os.path.abspath(sys.argv[1])
current = os.sep
for component in path.split(os.sep)[1:]:
    current = os.path.join(current, component)
    try:
        mode = os.lstat(current).st_mode
    except FileNotFoundError:
        break
    if stat.S_ISLNK(mode):
        raise SystemExit('refusing symlink output path: ' + current)
PY
}

check_or_write_github_ssh_config() {
  local mode="${1:-check}"
  python3 - "$GITHUB_SSH_CONFIG" "$GITHUB_SSH_KEY" "$GITHUB_SSH_MARKER" "$GITHUB_SSH_END_MARKER" "$mode" <<'PY'
import fnmatch
import os
import pathlib
import re
import shlex
import stat
import sys
import tempfile

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
marker = sys.argv[3]
end_marker = sys.argv[4]
mode = sys.argv[5]
original = path.read_text() if path.exists() else ''
lines = original.splitlines(keepends=True)

def check_block(hosts, identities):
    if not hosts:
        return
    positive = [item for item in hosts if not item.startswith('!')]
    negative = [item[1:] for item in hosts if item.startswith('!')]
    applies = any(fnmatch.fnmatch('github.com', item) for item in positive)
    applies = applies and not any(fnmatch.fnmatch('github.com', item) for item in negative)
    if applies:
        for identity in identities:
            if identity != key:
                raise SystemExit(
                    'conflicting github.com IdentityFile in ' + str(path) +
                    ': ' + identity + '; remove or reconcile it before GitHub bootstrap'
                )

in_own_block = False
hosts = []
identities = []
global_identities = []
seen_host = False
for line in lines:
    stripped = line.rstrip('\r\n')
    if stripped == marker:
        if not seen_host:
            check_block(['github.com'], global_identities)
        check_block(hosts, identities)
        hosts = []
        identities = []
        in_own_block = True
        continue
    if in_own_block:
        if stripped == end_marker:
            in_own_block = False
        continue
    host_match = re.match(r'^\s*Host\s+(.+?)\s*$', stripped, re.IGNORECASE)
    if host_match:
        check_block(hosts, identities)
        seen_host = True
        hosts = host_match.group(1).split()
        identities = list(global_identities)
        continue
    if re.match(r'^\s*Match\s+', stripped, re.IGNORECASE):
        check_block(hosts, identities)
        hosts = []
        identities = []
        continue
    if hosts:
        identity_match = re.match(r'^\s*IdentityFile\s+(.+?)\s*$', stripped, re.IGNORECASE)
        if identity_match:
            try:
                values = shlex.split(identity_match.group(1))
            except ValueError:
                values = [identity_match.group(1)]
            if values and not seen_host:
                global_identities.append(values[0])
            elif values:
                identities.append(values[0])
check_block(hosts, identities)
if not seen_host:
    check_block(['github.com'], global_identities)

if mode == 'check':
    raise SystemExit(0)

block = (
    marker + '\n'
    'Host github.com\n'
    '  HostName github.com\n'
    '  User git\n'
    '  IdentityFile ' + key + '\n'
    '  IdentitiesOnly yes\n'
    + end_marker + '\n'
)
rewritten = []
replaced = False
in_own_block = False
for line in lines:
    stripped = line.rstrip('\r\n')
    if stripped == marker:
        if not replaced:
            rewritten.append(block)
            replaced = True
        in_own_block = True
        continue
    if in_own_block:
        if stripped == end_marker:
            in_own_block = False
        continue
    rewritten.append(line)
if not replaced:
    if rewritten and not rewritten[-1].endswith('\n'):
        rewritten[-1] += '\n'
    rewritten.append(block)
new_content = ''.join(rewritten)
if new_content != original:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.github-config.', dir=str(path.parent), text=True)
    try:
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
        with os.fdopen(fd, 'w') as stream:
            stream.write(new_content)
        os.replace(temporary, str(path))
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
PY
}

verify_github_host_keys() {
  local scan_file fingerprint_file
  scan_file="$(mktemp "$GITHUB_SSH_DIR/.github-keyscan.XXXXXX")" || return 1
  fingerprint_file="$(mktemp "$GITHUB_SSH_DIR/.github-fingerprints.XXXXXX")" || {
    rm -f "$scan_file"
    return 1
  }
  chmod 0600 "$scan_file" "$fingerprint_file"
  if ! run_as_app_user_literal ssh-keyscan -T 10 -t ed25519,rsa github.com >"$scan_file"; then
    rm -f "$scan_file" "$fingerprint_file"
    fail 'could not scan GitHub host keys; no known_hosts entry was written'
  fi
  if ! run_as_app_user_literal ssh-keygen -lf "$scan_file" -E sha256 >"$fingerprint_file"; then
    rm -f "$scan_file" "$fingerprint_file"
    fail 'could not fingerprint scanned GitHub host keys; no known_hosts entry was written'
  fi
  if ! python3 - "$fingerprint_file" "$GITHUB_TRUSTED_ED25519_FINGERPRINT" "$GITHUB_TRUSTED_RSA_FINGERPRINT" <<'PY'
import pathlib
import sys

fingerprints = pathlib.Path(sys.argv[1]).read_text().splitlines()
trusted = {'ED25519': sys.argv[2], 'RSA': sys.argv[3]}
seen = {'ED25519': [], 'RSA': []}
for line in fingerprints:
    fields = line.split()
    if len(fields) < 2:
        continue
    kind = None
    if '(ED25519)' in fields:
        kind = 'ED25519'
    elif '(RSA)' in fields:
        kind = 'RSA'
    if kind is not None:
        seen[kind].append(fields[1])
for kind in ('ED25519', 'RSA'):
    if not seen[kind] or any(value != trusted[kind] for value in seen[kind]):
        raise SystemExit(
            'GitHub ' + kind + ' host fingerprint mismatch; expected ' + trusted[kind]
        )
PY
  then
    rm -f "$scan_file" "$fingerprint_file"
    fail 'GitHub host fingerprint verification failed; no known_hosts entry was written'
  fi
  GITHUB_VERIFIED_SCAN_FILE="$scan_file"
  GITHUB_VERIFIED_FINGERPRINTS_FILE="$fingerprint_file"
}

fingerprint_value() {
  awk '$2 ~ /^SHA256:/ { print $2; exit }'
}

ensure_github_key_pair() {
  local derived_file private_fingerprint public_fingerprint
  refuse_symlink_path "$GITHUB_SSH_KEY"
  refuse_symlink_path "$GITHUB_SSH_PUBLIC_KEY"

  if [[ ! -e "$GITHUB_SSH_KEY" && -e "$GITHUB_SSH_PUBLIC_KEY" ]]; then
    fail "GitHub public key exists without ${GITHUB_SSH_KEY}; remove the orphan only after verifying it is not registered"
  fi
  if [[ ! -e "$GITHUB_SSH_KEY" ]]; then
    run_as_app_user_literal ssh-keygen -q -t ed25519 -N '' -C 'openclaw-vps github' -f "$GITHUB_SSH_KEY" || \
      fail 'could not create the dedicated GitHub SSH key'
  fi

  derived_file="$(mktemp "$GITHUB_SSH_DIR/.github-public.XXXXXX")" || return 1
  chmod 0600 "$derived_file"
  if ! run_as_app_user_literal ssh-keygen -y -f "$GITHUB_SSH_KEY" >"$derived_file"; then
    rm -f "$derived_file"
    fail "could not read ${GITHUB_SSH_KEY}; refusing to replace the private key"
  fi
  private_fingerprint="$(run_as_app_user_literal ssh-keygen -lf "$derived_file" -E sha256 | fingerprint_value)" || {
    rm -f "$derived_file"
    fail 'could not fingerprint the dedicated GitHub private key'
  }

  if [[ -e "$GITHUB_SSH_PUBLIC_KEY" ]]; then
    public_fingerprint="$(run_as_app_user_literal ssh-keygen -lf "$GITHUB_SSH_PUBLIC_KEY" -E sha256 | fingerprint_value)" || {
      rm -f "$derived_file"
      fail 'could not fingerprint the existing GitHub public key'
    }
    if [[ -z "$private_fingerprint" || "$private_fingerprint" != "$public_fingerprint" ]]; then
      rm -f "$derived_file"
      fail "GitHub private/public key mismatch for ${GITHUB_SSH_KEY}; inspect the pair and do not replace the private key"
    fi
    rm -f "$derived_file"
  else
    mv "$derived_file" "$GITHUB_SSH_PUBLIC_KEY" || {
      rm -f "$derived_file"
      fail 'could not recover the missing GitHub public key'
    }
  fi

  chown "$APP_USER:$APP_USER" "$GITHUB_SSH_KEY" "$GITHUB_SSH_PUBLIC_KEY"
  chmod 0600 "$GITHUB_SSH_KEY"
  chmod 0644 "$GITHUB_SSH_PUBLIC_KEY"
}

append_verified_github_known_hosts() {
  python3 - "$GITHUB_KNOWN_HOSTS" "$GITHUB_VERIFIED_SCAN_FILE" <<'PY'
import os
import pathlib
import stat
import sys
import tempfile

known_hosts = pathlib.Path(sys.argv[1])
scan_file = pathlib.Path(sys.argv[2])
old = known_hosts.read_bytes() if known_hosts.exists() else b''
existing = set(line.rstrip(b'\r\n') for line in old.splitlines())
new = bytearray(old)
if new and not new.endswith(b'\n'):
    new.extend(b'\n')
for line in scan_file.read_bytes().splitlines():
    if line and line not in existing:
        new.extend(line + b'\n')
        existing.add(line)
new_bytes = bytes(new)
if new_bytes != old:
    fd, temporary = tempfile.mkstemp(prefix='.github-known-hosts.', dir=str(known_hosts.parent))
    try:
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(new_bytes)
        os.replace(temporary, str(known_hosts))
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
PY
  chown "$APP_USER:$APP_USER" "$GITHUB_KNOWN_HOSTS"
  chmod 0644 "$GITHUB_KNOWN_HOSTS"
}

prepare_github_ssh() {
  local fingerprints
  [[ "$GITHUB_SSH_KEY" != "$SANDBOX_SSH_KEY" ]] || \
    fail 'GitHub SSH key path must remain distinct from the provisioning/sandbox SSH key'
  refuse_symlink_path "$GITHUB_SSH_DIR"
  refuse_symlink_path "$GITHUB_SSH_KEY"
  refuse_symlink_path "$GITHUB_SSH_PUBLIC_KEY"
  refuse_symlink_path "$GITHUB_SSH_CONFIG"
  refuse_symlink_path "$GITHUB_KNOWN_HOSTS"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$GITHUB_SSH_DIR"
  chown "$APP_USER:$APP_USER" "$GITHUB_SSH_DIR"
  chmod 0700 "$GITHUB_SSH_DIR"

  # Check before scanning or creating anything so a pre-existing conflicting
  # IdentityFile cannot be hidden by a later Host github.com block.
  check_or_write_github_ssh_config check
  verify_github_host_keys
  ensure_github_key_pair
  check_or_write_github_ssh_config write
  chown "$APP_USER:$APP_USER" "$GITHUB_SSH_CONFIG"
  chmod 0600 "$GITHUB_SSH_CONFIG"
  append_verified_github_known_hosts

  fingerprints="$(cat "$GITHUB_VERIFIED_FINGERPRINTS_FILE")"
  rm -f "$GITHUB_VERIFIED_SCAN_FILE" "$GITHUB_VERIFIED_FINGERPRINTS_FILE"
  unset GITHUB_VERIFIED_SCAN_FILE GITHUB_VERIFIED_FINGERPRINTS_FILE
  printf 'GitHub SSH public key (register this key with GitHub):\n'
  cat "$GITHUB_SSH_PUBLIC_KEY"
  printf 'Verified GitHub host fingerprints:\n%s\n' "$fingerprints"
}

# No login shell here: env -i is the final boundary AFTER sudo/PAM/user startup.
# In particular no token override, GH_DEBUG, alternate config, or git injection
# environment can reach gh or git. Executables are resolved/verified beforehand.
run_github_clean() {
  sudo -u "$APP_USER" -H -- env -i HOME="$APP_HOME" PATH=/usr/local/bin:/usr/bin:/bin GIT_TERMINAL_PROMPT=0 "$@"
}

github_stored_login_works() {
  run_github_clean "$github_gh" auth status --hostname github.com >/dev/null 2>&1 &&
    run_github_clean "$github_gh" api --hostname github.com user --jq .login 2>/dev/null |
      python3 -c 'import re, sys
sys.exit(0 if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}", sys.stdin.read().strip()) else 1)' >/dev/null 2>&1
}

verify_github_persistence() {
  github_stored_login_works || return 1
  # Resolve the actual HTTPS helper and invoke it through git, without ever
  # printing its password response. An API-only token is not enough for success.
  run_github_clean "$github_git" config --get-urlmatch credential.helper https://github.com >/dev/null 2>&1 || return 1
  printf 'protocol=https\nhost=github.com\n\n' |
    run_github_clean "$github_git" credential fill 2>/dev/null |
    python3 -c 'import sys
fields = dict(line.rstrip("\n").split("=", 1) for line in sys.stdin if "=" in line)
sys.exit(0 if fields.get("username") and fields.get("password") else 1)' >/dev/null 2>&1
}

github_require_managed_installation() {
  local path
  [[ -d "$APP_HOME" && -s "$AGENTS_FILE" && -s "$GROUPS_FILE" && -s "$OPENCLAW_CONFIG_FILE" ]] || \
    fail 'github-bootstrap requires a usable managed OpenClaw installation'
  jq -e '.agents | type == "array" and length > 0' "$AGENTS_FILE" >/dev/null || fail 'no managed agents installed'
  jq -e '.groups | type == "array" and length > 0' "$GROUPS_FILE" >/dev/null || fail 'no managed groups installed'
  jq -e '.agents | type == "object"' "$OPENCLAW_CONFIG_FILE" >/dev/null || fail 'invalid managed OpenClaw config'
  jq -e --slurpfile managed "$AGENTS_FILE" --slurpfile groups "$GROUPS_FILE" '
    [.agents.list[]?, .agents.entries[]?] as $configured |
    all($managed[0].agents[]; . as $agent |
      any($configured[]; .id == $agent.id) and
      any($groups[0].groups[]; .id == $agent.group))
  ' "$OPENCLAW_CONFIG_FILE" >/dev/null || fail 'managed agents/groups are absent from the installed config'
  while IFS= read -r path; do
    [[ -d "$path" ]] || fail 'managed workspace is missing; repair installation before bootstrap'
  done < <(jq -r '.agents[].workspace' "$AGENTS_FILE")
  resolve_agent_state >/dev/null || fail 'managed agent state is not usable; repair it before bootstrap'
}

# Internal, fixed SSH transports. The token is staged privately by invocation ID
# so transfer can never overwrite existing working credentials before approval.
github_import_path() {
  [[ "$1" =~ ^[A-Za-z0-9]{6,64}$ ]] || fail 'invalid GitHub transfer identifier'
  printf '%s/.config/openclaw-vps/secrets/.GH_TOKEN.import.%s' "$APP_HOME" "$1"
}

cmd_github_token_stage() (
  set +x
  umask 077
  [[ $# == 1 ]] || fail 'GitHub staging requires a transfer identifier'
  require_root
  github_require_managed_installation
  staged_file="$(github_import_path "$1")"
  refuse_symlink_path "$staged_file" || exit 1
  [[ ! -e "$staged_file" ]] || fail 'GitHub transfer identifier already exists'
  for directory in "$APP_HOME/.config" "$APP_HOME/.config/openclaw-vps" "${staged_file%/*}"; do
    mkdir -p "$directory"
    chmod 700 "$directory"
    chown "$APP_USER:$APP_USER" "$directory"
  done
  staging_tmp="$(mktemp "${staged_file%/*}/.github-transfer.XXXXXX")"
  trap 'rm -f "$staging_tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  # Bounded pipe input, no token-bearing command arguments, trace, or diagnostics.
  python3 -c 'import sys
value = sys.stdin.buffer.read(8193)
if not value.strip() or len(value) > 8192 or b"\x00" in value:
    sys.exit(1)
sys.stdout.buffer.write(value)' >"$staging_tmp" || fail 'invalid GitHub credential transfer'
  chmod 600 "$staging_tmp"
  chown "$APP_USER:$APP_USER" "$staging_tmp"
  mv "$staging_tmp" "$staged_file"
)

cmd_github_token_discard() (
  set +x
  [[ $# == 1 ]] || fail 'GitHub discard requires a transfer identifier'
  require_root
  staged_file="$(github_import_path "$1")"
  refuse_symlink_path "$staged_file" || exit 1
  rm -f "$staged_file"
)

# Subshell keeps xtrace off through EXIT/rollback and restores the caller's shell
# options only after every secret variable and open credential fd is gone.
cmd_github_bootstrap() (
  set +x
  umask 077
  import_file=''
  if [[ $# != 0 ]]; then
    [[ $# == 2 && "$1" == --import-id ]] || fail 'github-bootstrap takes no token arguments; use its interactive terminal'
    import_file="$(github_import_path "$2")"
  fi
  path=''
  require_root
  [[ -t 0 ]] || fail 'github-bootstrap requires an interactive terminal; run the manager directly'
  exec 3<>/dev/tty || fail 'github-bootstrap requires a controlling terminal'
  github_require_managed_installation

  # Bash 3.2 unwinds function locals before EXIT on an explicit failure. These
  # variables belong to this subshell so rollback still has its complete state.
  github_gh='' github_git='' auth_dir='' secret_dir='' token_file='' answer='' token=''
  transaction='' committed=0 snapshot_ready=0 terminal_mode='' lock_dir=''
  paths=()
  index=0 saved='' rollback_ok=1
  github_gh="$(resolve_verified_host_tool gh)" || return 1
  github_git="$(resolve_verified_host_tool git)" || return 1
  auth_dir="$APP_HOME/.config/gh"
  secret_dir="$APP_HOME/.config/openclaw-vps/secrets"
  token_file="$secret_dir/GH_TOKEN"
  export -n token
  paths=("$auth_dir/hosts.yml" "$auth_dir/config.yml" "$APP_HOME/.gitconfig" "$APP_HOME/.config/git/config" "$token_file")
  # Refuse every parent/link before identity helpers, chmod, or credential writes.
  if [[ -n "$import_file" ]]; then
    refuse_symlink_path "$import_file" || return 1
    [[ -f "$import_file" && -s "$import_file" ]] || fail 'copied GitHub credential is missing; retry from the manager'
  fi
  for path in "${paths[@]}"; do
    refuse_symlink_path "$path" || return 1
    [[ ! -e "$path" || -f "$path" ]] || fail 'GitHub credential/config output must be a regular file'
  done
  for path in "$APP_HOME/.config" "$APP_HOME/.config/openclaw-vps" "$secret_dir" "$auth_dir"; do
    mkdir -p "$path"
    chmod 700 "$path"
    chown "$APP_USER:$APP_USER" "$path"
  done
  lock_dir="$secret_dir/.github-bootstrap.lock"
  mkdir "$lock_dir" 2>/dev/null || fail 'GitHub bootstrap already running; inspect any stale lock before retrying'
  github_bootstrap_cleanup() {
    local status=$?
    set +x
    unset token
    [[ -z "$import_file" ]] || rm -f "$import_file"
    # A disconnected terminal must not prevent credential rollback/lock cleanup.
    [[ -z "$terminal_mode" ]] || stty "$terminal_mode" <&3 2>/dev/null || true
    rollback_ok=1
    if [[ "$snapshot_ready" == 1 && "$committed" != 1 ]]; then
      index=0
      for path in "${paths[@]}"; do
        saved="$transaction/$index"
        if [[ -f "$saved" ]]; then
          # Each restore is a same-filesystem atomic rename of the private copy.
          mv -f "$saved" "$path" || rollback_ok=0
        else
          rm -f "$path" || rollback_ok=0
        fi
        index=$((index + 1))
      done
    fi
    if [[ "$rollback_ok" == 1 ]]; then
      [[ -z "$transaction" ]] || rm -rf "$transaction"
      rmdir "$lock_dir"
    else
      printf 'GitHub rollback failed; private recovery files retained at %s\n' "$transaction" >&2
      status=1
    fi
    exit "$status"
  }
  trap github_bootstrap_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  transaction="$(mktemp -d "$secret_dir/.github-transaction.XXXXXX")"
  index=0
  for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
      chmod 600 "$path"
      chown "$APP_USER:$APP_USER" "$path"
      cp -p "$path" "$transaction/$index"
    fi
    index=$((index + 1))
  done
  snapshot_ready=1
  seed_exec_allowlist || fail 'GitHub bootstrap failed to add git/gh approvals; retry after repairing approvals'
  ensure_git_identity <&3
  printf 'Optional GitHub SSH setup (separate from HTTPS login) [y/N]: ' >&3
  IFS= read -r answer <&3 || fail 'GitHub bootstrap cancelled'
  case "$answer" in y|Y|yes) prepare_github_ssh ;; esac

  answer=y
  # An API outage must never become implicit permission to replace credentials.
  # Also protect stored (possibly expired) material even when status is failing.
  if [[ -s "$auth_dir/hosts.yml" || -s "$token_file" ]] ||
     run_github_clean "$github_gh" auth status --hostname github.com >/dev/null 2>&1; then
    printf 'Replace existing GitHub login? [y/N]: ' >&3
    IFS= read -r answer <&3 || fail 'GitHub bootstrap cancelled; existing login preserved'
  fi
  case "$answer" in
    y|Y|yes)
      if [[ -n "$import_file" ]]; then
        cp "$import_file" "$transaction/token"
        rm -f "$import_file"
      else
        # Disable echo before publishing the prompt (including for PTY callers).
        terminal_mode="$(stty -g <&3)"
        stty -echo <&3
        printf 'GitHub token (hidden): ' >&3
        IFS= read -r -s token <&3 || fail 'GitHub token input failed; retry bootstrap'
        stty "$terminal_mode" <&3
        terminal_mode=''
        printf '\n' >&3
        [[ -n "$token" ]] || fail 'GitHub token is empty; retry bootstrap'
        printf '%s\n' "$token" > "$transaction/token"
        unset token
      fi
      chmod 600 "$transaction/token"
      chown "$APP_USER:$APP_USER" "$transaction/token"
      mv -f "$transaction/token" "$token_file"
      # Explicit file storage avoids mutating an OS keyring that rollback cannot restore.
      # stdin is the file, NEVER token-bearing argv or executable shell text.
      # Suppress both streams: a failed CLI may include the token in its error.
      run_github_clean "$github_gh" auth login --hostname github.com --git-protocol https --with-token --insecure-storage \
        < "$token_file" >/dev/null 2>&1 || fail 'GitHub login failed; check token type/scopes and retry bootstrap'
      ;;
  esac
  run_github_clean "$github_gh" auth setup-git --hostname github.com >/dev/null 2>&1 || \
    fail 'GitHub credential helper setup failed; retry bootstrap'
  for path in "${paths[@]}"; do
    refuse_symlink_path "$path" || return 1
    if [[ -f "$path" ]]; then
      chmod 600 "$path"
      chown "$APP_USER:$APP_USER" "$path"
    fi
  done
  verify_github_persistence || fail 'GitHub persistence verification failed; check token type/scopes and retry bootstrap'
  committed=1
  printf 'GitHub stored login, API identity, and HTTPS credential helper verified without token environment variables.\n'
  printf 'Credentials are shared by the service account; private token and gh config files must remain secret.\n'
)

run_as_app_user_with_env() {
  local command_text="$1"
  sudo -Hiu "$APP_USER" bash -lc "set -a; [[ -r '${USER_ENV_FILE}' ]] && . '${USER_ENV_FILE}'; set +a; export PATH='${USER_BIN_DIR}:/usr/local/bin:/usr/bin:/bin'; ${command_text}"
}

# All local OpenClaw operations use the gateway account, PATH and active state.
# The env file may select a nondefault state directory (including SQLite stores).
run_openclaw_local() {
  run_as_app_user_with_env "export HOME=$(shell_quote "$APP_HOME"); if [[ -z \${OPENCLAW_STATE_DIR:-} ]]; then export OPENCLAW_STATE_DIR=$(shell_quote "$OPENCLAW_CONFIG_DIR"); fi; if [[ -z \${OPENCLAW_CONFIG_PATH:-} ]]; then export OPENCLAW_CONFIG_PATH=$(shell_quote "$OPENCLAW_CONFIG_FILE"); fi; $1"
}

verify_system_executable() {
  python3 - "$1" <<'PY'
import os, pathlib, sys
try:
    p = pathlib.Path(sys.argv[1])
    if not p.is_absolute() or not p.is_file() or not os.access(p, os.X_OK):
        raise ValueError('not an absolute executable file')
    # Check both the PATH spelling and symlink target, including every ancestor.
    for path in (p, p.resolve(strict=True)):
        for item in (path, *path.parents):
            link = item.lstat()
            meta = item.stat()
            if link.st_uid != 0 or meta.st_uid != 0 or meta.st_mode & 0o022:
                raise ValueError('not root-owned or writable by group/others: ' + str(item))
except (OSError, ValueError) as exc:
    sys.exit('untrusted executable: ' + str(exc))
PY
}

resolve_verified_host_tool() {
  local path
  path="$(run_as_app_user "command -v $1")" || { warn "missing host tool: $1"; return 1; }
  verify_system_executable "$path" || return 1
  run_as_app_user "$(shell_quote "$path") --version" >/dev/null || { warn "host tool does not function: $1"; return 1; }
  printf '%s\n' "$path"
}

ensure_git_gh_installed() (
  # Pinned release: version, archive name and manifest always come from one tag.
  # Do not use an unverified latest redirect or a separately maintained digest.
  local version=2.78.0 arch name base tmp path
  path="$(run_as_app_user 'command -v git')" || path=''
  if [[ -z "$path" ]]; then
    apt-get install -y git || return 1
  fi
  resolve_verified_host_tool git >/dev/null || return 1
  path="$(run_as_app_user 'command -v gh')" || path=''
  if [[ -n "$path" ]]; then
    verify_system_executable "$path" || return 1
    if run_as_app_user "$(shell_quote "$path") --version" >/dev/null; then
      return 0
    fi
  fi
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) warn 'unsupported architecture for GitHub CLI release'; return 1 ;;
  esac
  name="gh_${version}_linux_${arch}"
  base="https://github.com/cli/cli/releases/download/v${version}"
  tmp="$(mktemp -d)" || return 1
  trap 'rm -rf "$tmp"' EXIT
  chmod 0700 "$tmp" || return 1
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$tmp/archive.tar.gz" "$base/$name.tar.gz" || return 1
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --output "$tmp/checksums.txt" "$base/gh_${version}_checksums.txt" || return 1
  # Verify the digest before even opening the archive. Inspect ALL members before
  # reading just bin/gh; no tar extraction ever writes attacker-chosen paths.
  python3 - "$tmp" "$name" <<'PY'
import hashlib, pathlib, re, sys, tarfile
try:
    root, name = pathlib.Path(sys.argv[1]), sys.argv[2]
    matches = []
    for line in (root / 'checksums.txt').read_text().splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip('*') == name + '.tar.gz':
            matches.append(fields[0])
    if len(matches) != 1 or not re.fullmatch('[a-fA-F0-9]{64}', matches[0]):
        raise ValueError('missing or ambiguous release checksum')
    archive = root / 'archive.tar.gz'
    if hashlib.sha256(archive.read_bytes()).hexdigest() != matches[0].lower():
        raise ValueError('release checksum mismatch')
    with tarfile.open(archive, 'r:gz') as tf:
        members = tf.getmembers()
        seen = set()
        executable = None
        for item in members:
            parts = item.name.split('/')
            if (item.name.startswith('/') or '..' in parts or '\\' in item.name
                    or parts[0] != name or item.name in seen
                    or not (item.isfile() or item.isdir())):
                raise ValueError('unsafe release archive member: ' + item.name)
            seen.add(item.name)
            if item.name == name + '/bin/gh':
                executable = item
        if executable is None or not executable.isfile() or not executable.mode & 0o111:
            raise ValueError('missing release executable')
        with tf.extractfile(executable) as source, (root / 'gh').open('xb') as dest:
            import shutil
            shutil.copyfileobj(source, dest)
except (OSError, ValueError, tarfile.TarError) as exc:
    sys.exit('GitHub CLI verification failed: ' + str(exc))
PY
  [[ "$?" == 0 ]] || return 1
  install -o root -g root -m 0755 "$tmp/gh" "$GH_INSTALL_PATH" || return 1
  resolve_verified_host_tool gh >/dev/null || return 1
)

# Capability adapter: config schema --json emits JSON Schema, with the exec
# object under properties.tools.properties.exec (verified locally in 2026.9.1).
# Legacy is accepted only when that local schema explicitly lists security/ask
# and has no mode. Unrecognized/ref-based shapes fail closed, never guess a version.
detect_exec_config_policy() {
  local schema
  schema="$(run_openclaw_local 'openclaw config schema --json' | jq -ce '.properties.tools.properties.exec.properties | select(type == "object")')" || { warn 'cannot determine supported exec schema'; return 1; }
  python3 - "$schema" "$OPENCLAW_CONFIG_FILE" <<'PY'
import json, pathlib, sys
try:
    props = json.loads(sys.argv[1])
    normalized = 'allowlist' in props.get('mode', {}).get('enum', [])
    legacy = ('mode' not in props and 'allowlist' in props.get('security', {}).get('enum', [])
              and 'off' in props.get('ask', {}).get('enum', []))
    if not (normalized or legacy) or props.get('strictInlineEval', {}).get('type') != 'boolean':
        raise ValueError('unsupported or ambiguous exec schema')
    path = pathlib.Path(sys.argv[2])
    try:
        current = json.loads(path.read_text()) if path.exists() else {}
    except json.JSONDecodeError:
        # Retain the generator's existing recovery for an unusable JSON file.
        current = {}
    old = current.get('tools', {}).get('exec') if isinstance(current, dict) else None
    if old is not None and not isinstance(old, dict):
        raise ValueError('invalid existing exec policy')
    if old is None or not {'mode', 'security', 'ask'}.intersection(old):
        policy = dict(old or {}, host='gateway')
        policy.setdefault('strictInlineEval', True)
        policy.update(dict(mode='allowlist') if normalized else dict(security='allowlist', ask='off'))
    else:
        policy = old.copy()
        if 'mode' in old and ('security' in old or 'ask' in old):
            raise ValueError('ambiguous existing exec policy')
        if normalized and 'mode' not in old:
            # Only lossless conversions. E.g. ask:always must not become on-miss.
            sec, ask = old.get('security'), old.get('ask')
            mapping = {('deny', 'off'): 'deny', ('allowlist', 'off'): 'allowlist',
                       ('allowlist', 'on-miss'): 'ask', ('full', 'off'): 'full'}
            if (sec, ask) not in mapping:
                raise ValueError('existing exec policy cannot be normalized without changing policy')
            policy.pop('security'); policy.pop('ask')
            policy['mode'] = mapping[(sec, ask)]
        if legacy and 'mode' in old:
            raise ValueError('installed legacy schema cannot preserve existing mode policy')
        field = 'mode' if normalized else 'security'
        if policy.get(field) not in props.get(field, {}).get('enum', []):
            raise ValueError('unsupported existing exec policy')
    print(json.dumps(policy))
except (OSError, ValueError, KeyError, TypeError) as exc:
    sys.exit('unsupported exec schema/policy: ' + str(exc))
PY
}

validate_openclaw_config() {
  chown "$APP_USER:$APP_USER" "$1" || return 1
  chmod 0600 "$1" || return 1
  run_openclaw_local "OPENCLAW_CONFIG_PATH=$(shell_quote "$1") openclaw config validate --json" >/dev/null || {
    warn 'generated OpenClaw config validation failed; current config preserved'
    return 1
  }
}

install_openclaw_and_opencode() {
  log "installing OpenClaw and OpenCode into ${APP_USER}'s local npm prefix"
  run_as_app_user "mkdir -p '${USER_BIN_DIR}' '${APP_HOME}/.npm-global' && npm config set prefix '${APP_HOME}/.local'"
  run_as_app_user "npm install -g openclaw@latest opencode-ai@latest"
  run_as_app_user "openclaw --version || true"
  run_as_app_user "opencode --version || true"
}

write_user_env() {
  resolve_openclaw_timezone
  local model_provider="$1" model_base_url="$2" model_api_key="$3" model_id="$4" model_catalog="$5"
  local telegram_token="$6"
  local gateway_token
  gateway_token="$(openssl rand -hex 32 2>/dev/null || date +%s%N | sha256sum | awk '{print $1}')"

  log "writing secret environment file for ${APP_USER}"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$USER_CONFIG_DIR"
  {
    printf 'MODEL_PROVIDER=%s\n' "$(shell_quote "$model_provider")"
    printf 'MODEL_BASE_URL=%s\n' "$(shell_quote "$model_base_url")"
    printf 'MODEL_API_KEY=%s\n' "$(shell_quote "$model_api_key")"
    printf 'MODEL_ID=%s\n' "$(shell_quote "$model_id")"
    if [[ -n "$model_catalog" ]]; then
      printf 'MODEL_CATALOG=%s\n' "$(shell_quote "$model_catalog")"
    fi
    printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(shell_quote "$gateway_token")"
    printf 'OPENCLAW_CONFIG_PATH=%s\n' "$(shell_quote "$OPENCLAW_CONFIG_FILE")"
    printf 'OPENCLAW_STATE_DIR=%s\n' "$(shell_quote "$OPENCLAW_CONFIG_DIR")"
    printf 'NODE_COMPILE_CACHE=%s\n' "$(shell_quote "/var/tmp/openclaw-compile-cache")"
    printf 'OPENCLAW_TIMEZONE=%s\n' "$(shell_quote "$OPENCLAW_TIMEZONE")"
    printf 'TZ=%s\n' "$(shell_quote "$OPENCLAW_TIMEZONE")"
    printf 'OPENCLAW_NO_RESPAWN=1\n'
    if [[ -n "$telegram_token" ]]; then
      printf 'TELEGRAM_BOT_TOKEN=%s\n' "$(shell_quote "$telegram_token")"
    fi
  } >"$USER_ENV_FILE"
  chown "$APP_USER:$APP_USER" "$USER_ENV_FILE"
  chmod 0600 "$USER_ENV_FILE"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0775 /var/tmp/openclaw-compile-cache
}

ensure_user_shell_sources_env() {
  local bashrc="${APP_HOME}/.bashrc"
  local marker="openclaw-vps managed environment"
  touch "$bashrc"
  chown "$APP_USER:$APP_USER" "$bashrc"
  if ! grep -q "$marker" "$bashrc"; then
    cat >>"$bashrc" <<EOF

# ${marker}
if [ -r "\$HOME/.config/openclaw-vps/env" ]; then
  set -a
  . "\$HOME/.config/openclaw-vps/env"
  set +a
fi
export PATH="\$HOME/.local/bin:\$PATH"
EOF
    chown "$APP_USER:$APP_USER" "$bashrc"
  fi
}

regenerate_openclaw_config() {
  local resolved_agents exec_policy
  resolved_agents="$(resolve_agent_state)" || return 1
  exec_policy="$(detect_exec_config_policy)" || return 1
  load_model_env_from_file
  resolve_openclaw_timezone
  log "writing OpenClaw config for ${MODEL_PROVIDER:-configured provider} ${MODEL_ID}"

  sync_all_agent_workspace_skills
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$OPENCLAW_CONFIG_DIR"

  local preserve_file config_tmp
  preserve_file="$(mktemp "${OPENCLAW_CONFIG_DIR}/openclaw-preserve.XXXXXX")"
  config_tmp="$(mktemp "${OPENCLAW_CONFIG_DIR}/openclaw-refresh.XXXXXX")"
  trap 'trap - RETURN; rm -f "${preserve_file:-}" "${config_tmp:-}"' RETURN

  if [[ -f "$OPENCLAW_CONFIG_FILE" ]] && \
     jq -e 'type == "object"' "$OPENCLAW_CONFIG_FILE" >/dev/null 2>&1 && \
     jq '
       def obj: if type == "object" then . else {} end;
       {
         plugins: (((.plugins // {}) | obj) | del(.installs)),
         mcp: ((.mcp // {}) | obj),
         secrets: ((.secrets // {}) | obj),
         toolsWeb: ((.tools.web // {}) | obj)
       }
     ' "$OPENCLAW_CONFIG_FILE" >"$preserve_file"; then
    :
  else
    printf '{}' >"$preserve_file"
    warn "current OpenClaw config is missing or invalid; refreshing without operator-owned sections"
  fi

  if ! jq -n \
    --argjson agents "[$resolved_agents]" \
    --argjson execPolicy "$exec_policy" \
    --slurpfile preserved "$preserve_file" \
    --arg provider "$MODEL_PROVIDER" \
    --arg baseUrl "$MODEL_BASE_URL" \
    --arg model "$MODEL_ID" \
    --arg catalogCsv "$MODEL_CATALOG" \
    --arg skillsCsv "$OPENCLAW_AGENT_SKILLS" \
    --arg port "$OPENCLAW_PORT" \
    --arg timezone "$OPENCLAW_TIMEZONE" \
    --arg defaultAgent "$DEFAULT_AGENT_ID" \
    '
    def envref($name): "${" + $name + "}";
    def skill_allowlist: ($skillsCsv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")));
    ($agents[0].agents | map(select(.telegramTokenEnv != ""))) as $telegramAgents |
    (($agents[0].agents | map(select(.default == true)) | .[0].id) // $agents[0].agents[0].id // $defaultAgent) as $defaultAgent |
    def telegram_elevated_ids:
      [$telegramAgents[] | select(.telegramAllowFrom != "") | .telegramAllowFrom] as $ids |
      ($ids | map((sub("^tg:"; "")) as $bare | ["tg:" + $bare, $bare, "telegram:" + $bare]) | add // [] | unique);
    (skill_allowlist) as $skillAllowlist |
    {
      env: { MODEL_API_KEY: envref("MODEL_API_KEY") },
      models: {
        mode: "merge",
        providers: {
          ($provider): {
            baseUrl: $baseUrl,
            apiKey: envref("MODEL_API_KEY"),
            api: "openai-completions",
            models: (
              (($catalogCsv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))) + [$model]) | unique |
              map({ id: (split("/") | last), name: . })
            )
          }
        }
      },
      gateway: {
        mode: "local",
        bind: "loopback",
        port: ($port | tonumber),
        auth: {
          mode: "token",
          token: envref("OPENCLAW_GATEWAY_TOKEN")
        },
        reload: { mode: "hybrid" },
        trustedProxies: ["127.0.0.1", "::1"]
      },
      agents: {
        defaults: {
          workspace: ($agents[0].agents[] | select(.id == $defaultAgent) | .workspace),
          userTimezone: $timezone,
          model: { primary: $model }
        },
        list: [
          $agents[0].agents[] |
          {
            id: .id,
            name: .id,
            identity: {name: (.label // .id)},
            default: (.id == $defaultAgent),
            workspace: .workspace,
            agentDir: .agentDir,
            model: { primary: $model },
            sandbox: .sandbox
          }
          + (if (.subagents? | type) == "object" then {subagents: .subagents} else {} end)
          + (if (.skills? | type) == "array" then {skills: .skills}
             elif ($skillAllowlist | length) > 0 then {skills: $skillAllowlist}
             else {} end)
          + (if (.contextInjection? | type) == "string" then {contextInjection: .contextInjection} else {} end)
          + (if (.bootstrapMaxChars? | type) == "number" then {bootstrapMaxChars: .bootstrapMaxChars} else {} end)
          + (if (.bootstrapTotalMaxChars? | type) == "number" then {bootstrapTotalMaxChars: .bootstrapTotalMaxChars} else {} end)
          + (if (.tools? | type) == "object" then {tools: .tools} else {} end)
          + (if (.heartbeat? | type) == "object" then {heartbeat: .heartbeat} else {} end)
        ]
      },
      tools: {
        profile: "coding",
        elevated: {
          enabled: ((telegram_elevated_ids | length) > 0),
          allowFrom: { telegram: telegram_elevated_ids }
        },
        exec: $execPolicy,
        loopDetection: {
          enabled: true,
          historySize: 30,
          warningThreshold: 10,
          criticalThreshold: 20,
          globalCircuitBreakerThreshold: 30
        }
      },
      messages: {
        visibleReplies: "automatic",
        groupChat: { visibleReplies: "automatic" }
      }
    }
    + (if ($telegramAgents | length) > 0 then {
      bindings: [
        $telegramAgents[] | {
          agentId: .id,
          match: { channel: "telegram", accountId: .telegramAccount }
        }
      ],
      channels: {
        telegram: {
          enabled: true,
          accounts: (
            reduce $telegramAgents[] as $agent ({};
              .[$agent.telegramAccount] = (
                {
                  botToken: envref($agent.telegramTokenEnv),
                  dmPolicy: (if $agent.telegramAllowFrom == "" then "pairing" else "allowlist" end),
                  groupPolicy: "allowlist",
                  groups: { "*": { requireMention: true } }
                }
                + (if $agent.telegramAllowFrom == "" then {} else { allowFrom: [$agent.telegramAllowFrom] } end)
              )
            )
          )
        }
      }
    } else {} end)
    + ([$telegramAgents[] | select(.ownerAllowFrom != "") | .ownerAllowFrom] as $owners | if ($owners | length) > 0 then { commands: { ownerAllowFrom: $owners } } else {} end)
    | ($preserved[0] // {}) as $p
    | if ($p.plugins | length) > 0 then .plugins = $p.plugins else . end
    | if ($p.mcp | length) > 0 then .mcp = $p.mcp else . end
    | if ($p.secrets | length) > 0 then .secrets = $p.secrets else . end
    | if ($p.toolsWeb | length) > 0 then .tools.web = $p.toolsWeb else . end
    ' >"$config_tmp"; then
    return 1
  fi
  if ! jq -e 'type == "object"' "$config_tmp" >/dev/null; then
    return 1
  fi
  validate_openclaw_config "$config_tmp" || return 1
  mv "$config_tmp" "$OPENCLAW_CONFIG_FILE"
  chown "$APP_USER:$APP_USER" "$OPENCLAW_CONFIG_FILE"
  chmod 0600 "$OPENCLAW_CONFIG_FILE"
}

write_openclaw_config() {
  regenerate_openclaw_config
}

write_opencode_config() {
  load_model_env_from_file
  log "writing OpenCode config for ${MODEL_PROVIDER:-configured provider} ${MODEL_ID}"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$OPENCODE_CONFIG_DIR"
  jq -n --arg provider "$MODEL_PROVIDER" --arg baseUrl "$MODEL_BASE_URL" --arg model "$MODEL_ID" '
    {"$schema": "https://opencode.ai/config.json", model: $model, small_model: $model,
     share: "disabled", autoupdate: false,
     provider: {($provider): {npm: "@ai-sdk/openai-compatible", name: $provider,
       options: {baseURL: $baseUrl, apiKey: "{env:MODEL_API_KEY}"},
       models: {($model | split("/") | last): {name: $model}}}},
     permission: {bash: "ask", edit: "ask", write: "ask"}}' >"$OPENCODE_CONFIG_FILE"
  chown "$APP_USER:$APP_USER" "$OPENCODE_CONFIG_FILE"
  chmod 0600 "$OPENCODE_CONFIG_FILE"
}

load_model_env_from_file() {
  # Refresh flows run without MODEL_* in the environment; load them from the
  # managed env file so config regeneration works on an installed box.
  if [[ -r "$USER_ENV_FILE" ]]; then
    if [[ -z "$MODEL_PROVIDER" || -z "$MODEL_BASE_URL" || -z "$MODEL_ID" || -z "$MODEL_API_KEY" || -z "$MODEL_CATALOG" || -z "${ZAI_API_KEY:-}" ]]; then
      local loaded_model_env name value
      loaded_model_env="$(bash -c 'set -a; . "$1" >/dev/null 2>&1; set +a; for v in MODEL_PROVIDER MODEL_BASE_URL MODEL_API_KEY MODEL_ID MODEL_CATALOG ZAI_API_KEY; do case "$v" in MODEL_PROVIDER) value="${MODEL_PROVIDER:-}" ;; MODEL_BASE_URL) value="${MODEL_BASE_URL:-}" ;; MODEL_API_KEY) value="${MODEL_API_KEY:-}" ;; MODEL_ID) value="${MODEL_ID:-}" ;; MODEL_CATALOG) value="${MODEL_CATALOG:-}" ;; ZAI_API_KEY) value="${ZAI_API_KEY:-}" ;; esac; printf "%s=%q\n" "$v" "$value"; done' bash "$USER_ENV_FILE")"
      while IFS='=' read -r name value; do
        case "$name" in
          MODEL_PROVIDER) [[ -z "$MODEL_PROVIDER" ]] && eval "$name=$value" ;;
          MODEL_BASE_URL) [[ -z "$MODEL_BASE_URL" ]] && eval "$name=$value" ;;
          MODEL_API_KEY) [[ -z "$MODEL_API_KEY" ]] && eval "$name=$value" ;;
          MODEL_ID) [[ -z "$MODEL_ID" ]] && eval "$name=$value" ;;
          MODEL_CATALOG) [[ -z "$MODEL_CATALOG" ]] && eval "$name=$value" ;;
          ZAI_API_KEY) [[ -z "${ZAI_API_KEY:-}" ]] && eval "$name=$value" ;;
        esac
      done <<< "$loaded_model_env"
    fi
    if [[ -z "$MODEL_API_KEY" && -n "${ZAI_API_KEY:-}" ]]; then
      MODEL_API_KEY="$ZAI_API_KEY"
      log "legacy ZAI_API_KEY found in env file; using it as MODEL_API_KEY (migrate the env file when convenient)"
    fi
    if [[ -z "$MODEL_PROVIDER" && -n "${ZAI_API_KEY:-}" ]]; then
      MODEL_PROVIDER=zai
      MODEL_BASE_URL="${MODEL_BASE_URL:-https://api.z.ai/api/coding/paas/v4}"
      MODEL_ID="${MODEL_ID:-zai/glm-5.3}"
    fi
  fi
  discover_model_catalog
}

discover_model_catalog() {
  local hdr base response ids catalog id count
  if [[ -n "$MODEL_CATALOG" || -z "$MODEL_BASE_URL" || -z "$MODEL_API_KEY" || -z "$MODEL_PROVIDER" ]]; then
    return 0
  fi

  hdr="$(mktemp)" || {
    [[ -n "$MODEL_ID" ]] && log "provider catalog endpoint unavailable; using configured model list"
    return 0
  }
  if ! chmod 600 "$hdr" 2>/dev/null; then
    rm -f "$hdr"
    [[ -n "$MODEL_ID" ]] && log "provider catalog endpoint unavailable; using configured model list"
    return 0
  fi
  if ! printf 'Authorization: Bearer %s\n' "$MODEL_API_KEY" >"$hdr"; then
    rm -f "$hdr"
    [[ -n "$MODEL_ID" ]] && log "provider catalog endpoint unavailable; using configured model list"
    return 0
  fi

  base="${MODEL_BASE_URL%/}"
  response="$(curl -s -m 10 -H @"$hdr" "$base/models" 2>/dev/null || true)"
  rm -f "$hdr"
  ids="$(printf '%s' "$response" | jq -r '[(.data[]?.id? // empty), (.models[]?.id? // empty)] | map(select(. != "")) | unique | sort | .[]' 2>/dev/null || true)"
  if [[ -z "$ids" ]]; then
    [[ -n "$MODEL_ID" ]] && log "provider catalog endpoint unavailable; using configured model list"
    return 0
  fi

  catalog=""
  count=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    catalog="${catalog}${MODEL_PROVIDER}/${id},"
    count=$((count + 1))
  done <<< "$ids"
  MODEL_CATALOG="${catalog%,}"
  log "discovered $count models from provider catalog endpoint"
}

seed_provider_auth() {
  load_model_env_from_file
  local provider key agent_id
  provider="$MODEL_PROVIDER"
  key="$MODEL_API_KEY"
  if [[ -z "$provider" || -z "$key" ]]; then
    return 0
  fi

  while IFS= read -r agent_id; do
    [[ -n "$agent_id" ]] || continue
    if ! printf '%s' "$key" | run_as_app_user_with_env "openclaw models auth paste-token --provider $(shell_quote "$provider") --agent $(shell_quote "$agent_id")"; then
      warn "provider auth seed failed; run paste-token manually"
    fi
  done < <(jq -r --arg default "$DEFAULT_AGENT_ID" '([.agents[]?.id] | map(select(. == $default)) + map(select(. != $default)))[]?' "$AGENTS_FILE")
}

install_user_systemd_service() {
  log "installing OpenClaw as a systemd user service for ${APP_USER}"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$USER_SYSTEMD_DIR"
  cat >"${USER_SYSTEMD_DIR}/${OPENCLAW_SERVICE}" <<EOF
[Unit]
Description=OpenClaw Gateway (native VPS POC)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_HOME}
Environment=PATH=${USER_BIN_DIR}:/usr/local/bin:/usr/bin:/bin
Environment=TZ=${OPENCLAW_TIMEZONE}
EnvironmentFile=${USER_ENV_FILE}
ExecStart=${USER_BIN_DIR}/openclaw gateway
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  chown "$APP_USER:$APP_USER" "${USER_SYSTEMD_DIR}/${OPENCLAW_SERVICE}"
  chmod 0600 "${USER_SYSTEMD_DIR}/${OPENCLAW_SERVICE}"
  loginctl enable-linger "$APP_USER"
  local uid
  uid="$(id -u "$APP_USER")"
  systemctl start "user@${uid}.service"
  runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user daemon-reload
  runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user enable --now "$OPENCLAW_SERVICE"
}

write_sandbox_dependency_audit() {
  cat >/usr/local/sbin/openclaw-vps-sandbox-audit <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"
GROUPS_FILE="${GROUPS_FILE}"
NODE_MAJOR="${NODE_MAJOR}"
AGENTS_FILE="${AGENTS_FILE}"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_FILE}"
APP_HOME="${APP_HOME}"

$(declare -f resolve_agent_state)
GROUPS_FILE="${GROUPS_FILE}"
SANDBOX_SSH_KEY="${SANDBOX_SSH_KEY}"
SANDBOX_KNOWN_HOSTS_DIR="${SANDBOX_KNOWN_HOSTS_DIR}"

extract_required_bins() {
  local skill_file="\$1"
  grep -E '"(bins|anyBins)"[[:space:]]*:' "\$skill_file" 2>/dev/null \
    | grep -Eo '"[A-Za-z0-9_.+-]+"' \
    | tr -d '"' \
    | grep -Ev '^(bins|anyBins)$' || true
}

extract_required_env() {
  local skill_file="\$1"
  grep -E '"env"[[:space:]]*:' "\$skill_file" 2>/dev/null \
    | grep -Eo '"[A-Z][A-Z0-9_]+"' \
    | tr -d '"' || true
  grep -E '"primaryEnv"[[:space:]]*:' "\$skill_file" 2>/dev/null \
    | grep -Eo '"[A-Z][A-Z0-9_]+"' \
    | tr -d '"' || true
}

check_bin() {
  sandbox_run "\$1" "\$2" "command -v \$(printf '%q' "\$3") >/dev/null 2>&1"
}

# mode/backend come from the resolved policy for this agent, never its Incus group.
sandbox_run() {
  local command_text="\$3"
  if [[ "\$sandbox_mode" == off ]]; then
    sudo -Hiu "\$APP_USER" bash -lc "set -a; [[ ! -r '\$USER_ENV_FILE' ]] || . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; cd \$(printf '%q' "\$workspace"); \$command_text"
  elif [[ "\$sandbox_backend" == ssh ]]; then
    local target port identity known_hosts strict update remote_workspace
    local -a options=()
    target="\$(jq -r '.sandbox.ssh.target' <<<"\$agent_row")"
    identity="\$(jq -r '.sandbox.ssh.identityFile // empty' <<<"\$agent_row")"
    known_hosts="\$(jq -r '.sandbox.ssh.knownHostsFile // empty' <<<"\$agent_row")"
    strict="\$(jq -r 'if .sandbox.ssh.strictHostKeyChecking == false then "no" else "yes" end' <<<"\$agent_row")"
    update="\$(jq -r 'if .sandbox.ssh.updateHostKeys == true then "yes" else "no" end' <<<"\$agent_row")"
    remote_workspace="\$(jq -r '.sandbox.ssh.workspaceRoot // empty' <<<"\$agent_row")"
    if [[ "\$target" =~ :[0-9]+$ ]]; then
      port="\${target##*:}"
      target="\${target%:*}"
      options+=( -p "\$port" )
    fi
    [[ -z "\$identity" ]] || options+=( -i "\$identity" )
    [[ -z "\$known_hosts" ]] || options+=( -o "UserKnownHostsFile=\$known_hosts" )
    [[ -z "\$remote_workspace" ]] || command_text="cd \$(printf '%q' "\$remote_workspace"); \$command_text"
    sudo -Hiu "\$APP_USER" ssh -o BatchMode=yes -o "StrictHostKeyChecking=\$strict" -o "UpdateHostKeys=\$update" "\${options[@]}" "\$target" "\$command_text"
  else
    printf 'UNVERIFIED dependency backend: %s (no host/container substitution)\n' "\$sandbox_backend" >&2
    return 1
  fi
}

check_sandbox_runtime() {
  local port="\$1"
  local known_hosts="\$2"
  local missing_count=0 node_major
  node_major="\$(sandbox_run "\$port" "\$known_hosts" 'node -p '\''process.versions.node.split(".")[0]'\'' 2>/dev/null || printf 0' || true)"
  if [[ "\${node_major:-0}" -lt "\$NODE_MAJOR" ]]; then
    printf 'MISSING node major >= %s, got %s\n' "\$NODE_MAJOR" "\${node_major:-0}"
    missing_count="\$((missing_count + 1))"
  fi
  if ! sandbox_run "\$port" "\$known_hosts" 'npm --version >/dev/null'; then
    printf 'MISSING npm\n'
    missing_count="\$((missing_count + 1))"
  fi
  if ! sandbox_run "\$port" "\$known_hosts" 'python3 -c '\''import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)'\'''; then
    printf 'MISSING python3 >= 3.12\n'
    missing_count="\$((missing_count + 1))"
  fi
  if ! sandbox_run "\$port" "\$known_hosts" 'python3 -m pip --version >/dev/null'; then
    printf 'MISSING python pip\n'
    missing_count="\$((missing_count + 1))"
  fi
  if ! sandbox_run "\$port" "\$known_hosts" 'python3 -c '\''import venv, ensurepip'\'''; then
    printf 'MISSING python3 -m venv\n'
    missing_count="\$((missing_count + 1))"
  fi
  if ! sandbox_run "\$port" "\$known_hosts" 'export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"; uv --version >/dev/null'; then
    printf 'MISSING uv\n'
    missing_count="\$((missing_count + 1))"
  fi
  return "\$missing_count"
}

visible_skill_files() {
  local agent_id="\$1"
  local workspace="\$2"
  local names=""
  names="\$(sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; openclaw skills --agent '\$agent_id' list --json" 2>/dev/null | jq -r '.skills[]? | select(.modelVisible == true) | .name' || true)"
  if [[ -n "\$names" ]]; then
    while IFS= read -r skill_name; do
      [[ -n "\$skill_name" ]] || continue
      [[ -f "\$workspace/skills/\$skill_name/SKILL.md" ]] && printf '%s\n' "\$workspace/skills/\$skill_name/SKILL.md"
    done <<<"\$names"
    return 0
  fi
  find "\$workspace/skills" -maxdepth 3 -name SKILL.md 2>/dev/null
}

resolved_agents="\$(resolve_agent_state)"
missing_count=0
while IFS= read -r agent_row; do
  agent_id="\$(jq -r '.id' <<<"\$agent_row")"
  group_id="\$(jq -r '.group' <<<"\$agent_row")"
  workspace="\$(jq -r '.workspace' <<<"\$agent_row")"
  sandbox_mode="\$(jq -r '.sandbox.mode' <<<"\$agent_row")"
  sandbox_backend="\$(jq -r 'if .sandbox.mode == "off" then "host" else (.sandbox.backend // "docker") end' <<<"\$agent_row")"
  exec_host="\$(jq -r --arg id "\$agent_id" '. as \$config | ([.agents.list[]? | select(.id == \$id)][0].tools.exec.host // .agents.entries[\$id].tools.exec.host // \$config.tools.exec.host // "gateway")' "\$OPENCLAW_CONFIG_FILE")"
  port=""
  known_hosts=""
  printf '== agent %s workspace=%s sandbox=%s backend=%s exec=%s ==\n' "\$agent_id" "\$workspace" "\$sandbox_mode" "\$sandbox_backend" "\$exec_host"
  if check_sandbox_runtime "\$port" "\$known_hosts"; then
    printf 'OK runtime node major >= %s, npm, python3 >= 3.12, pip, venv, uv\n' "\$NODE_MAJOR"
  else
    printf 'MISSING execution runtime dependency for agent %s\n' "\$agent_id"
    missing_count="\$((missing_count + 1))"
  fi
  for bin in git gh; do
    if check_bin "\$port" "\$known_hosts" "\$bin"; then
      printf 'OK bin %s\n' "\$bin"
    else
      printf 'MISSING bin %s\n' "\$bin"
      missing_count="\$((missing_count + 1))"
    fi
  done
  if [[ ! -d "\$workspace/skills" ]]; then
    printf 'WARN missing skills directory: %s\n' "\$workspace/skills"
    continue
  fi

  while IFS= read -r bin; do
    [[ -n "\$bin" ]] || continue
    if check_bin "\$port" "\$known_hosts" "\$bin"; then
      printf 'OK bin %s\n' "\$bin"
    else
      printf 'MISSING bin %s\n' "\$bin"
      missing_count="\$((missing_count + 1))"
    fi
  done < <(while IFS= read -r skill_file; do extract_required_bins "\$skill_file"; done < <(visible_skill_files "\$agent_id" "\$workspace") | sort -u)

  while IFS= read -r env_name; do
    [[ -n "\$env_name" ]] || continue
    printf 'TODO env %s requires explicit sandbox propagation decision\n' "\$env_name"
  done < <(while IFS= read -r skill_file; do extract_required_env "\$skill_file"; done < <(visible_skill_files "\$agent_id" "\$workspace") | sort -u)
done < <(jq -c '.agents[]?' <<<"\$resolved_agents")

exit "\$missing_count"
EOF
  chmod 0755 /usr/local/sbin/openclaw-vps-sandbox-audit
}

write_host_action_helper() {
  cat >"$HOST_ACTION_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

APP_USER="${APP_USER}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"

usage() {
  printf "Usage: %s {install-skill SLUG|update-skills|refresh-config|sandbox-audit|doctor|restart-vps|as-openclaw COMMAND...|as-root COMMAND...|write-file-base64 PATH BASE64 [OWNER] [MODE]}\\n" "\$0" >&2
}

if [[ "\${EUID}" -ne 0 ]]; then
  exec sudo -n "\$0" "\$@"
fi

run_as_openclaw() {
  local workspace
  workspace="\$(jq -r '(.agents | map(select(.default == true)) | .[0].workspace) // .agents[0].workspace // empty' "\$AGENTS_FILE")"
  if [[ -n "\$workspace" ]]; then
    sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; cd \"\$workspace\"; \$*"
  else
    sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; \$*"
  fi
}

write_file_base64() {
  local path="\$1"
  local payload="\$2"
  local owner="\${3:-\$APP_USER:\$APP_USER}"
  local mode="\${4:-0600}"
  [[ "\$payload" =~ ^[A-Za-z0-9+/=]+$ ]] || {
    printf 'invalid base64 payload\n' >&2
    exit 64
  }
  install -d -m 0755 "\$(dirname "\$path")"
  printf '%s' "\$payload" | base64 -d >"\$path"
  chown "\$owner" "\$path"
  chmod "\$mode" "\$path"
}

validate_skill_slug() {
  [[ "\$1" =~ ^[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)?$ ]] || {
    printf "invalid skill slug: %s\\n" "\$1" >&2
    exit 64
  }
}

case "\${1:-}" in
  install-skill)
    [[ -n "\${2:-}" && \$# -eq 2 ]] || { usage; exit 64; }
    validate_skill_slug "\$2"
    run_as_openclaw "openclaw skills install '\$2'"
    /root/openclaw-vps.sh refresh-config
    /usr/local/sbin/openclaw-vps-sandbox-audit
    ;;
  update-skills)
    [[ \$# -eq 1 ]] || { usage; exit 64; }
    run_as_openclaw "openclaw skills update --all"
    /root/openclaw-vps.sh refresh-config
    /usr/local/sbin/openclaw-vps-sandbox-audit
    ;;
  refresh-config)
    [[ \$# -eq 1 ]] || { usage; exit 64; }
    /root/openclaw-vps.sh refresh-config
    ;;
  sandbox-audit)
    [[ \$# -eq 1 ]] || { usage; exit 64; }
    /usr/local/sbin/openclaw-vps-sandbox-audit
    ;;
  doctor)
    [[ \$# -eq 1 ]] || { usage; exit 64; }
    /root/openclaw-vps.sh doctor
    ;;
  restart-vps)
    [[ \$# -eq 1 ]] || { usage; exit 64; }
    systemctl reboot
    ;;
  as-openclaw)
    shift
    [[ \$# -gt 0 ]] || { usage; exit 64; }
    run_as_openclaw "\$*"
    ;;
  as-root)
    shift
    [[ \$# -gt 0 ]] || { usage; exit 64; }
    bash -lc "\$*"
    ;;
  write-file-base64)
    [[ \$# -ge 3 && \$# -le 5 ]] || { usage; exit 64; }
    write_file_base64 "\$2" "\$3" "\${4:-}" "\${5:-}"
    ;;
  *)
    usage
    exit 64
    ;;
esac
EOF
  chown root:root "$HOST_ACTION_SCRIPT"
  chmod 0755 "$HOST_ACTION_SCRIPT"
  {
    printf '%s\n' "${APP_USER} ALL=(root) NOPASSWD: ${HOST_ACTION_SCRIPT}"
    printf '%s\n' "${APP_USER} ALL=(root) NOPASSWD: ALL"
  } >/etc/sudoers.d/openclaw-vps-host-action
  chmod 0440 /etc/sudoers.d/openclaw-vps-host-action
  visudo -cf /etc/sudoers.d/openclaw-vps-host-action >/dev/null
}

write_exec_approvals() {
  install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$STATE_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$OPENCLAW_CONFIG_DIR"
  local pending_tmp
  pending_tmp="$(mktemp "${STATE_DIR}/exec-approvals.XXXXXX")" || return 1
  chmod 0600 "$pending_tmp" || return 1
  cat >"$pending_tmp" <<EOF
{
  "version": 1,
  "defaults": {
    "security": "allowlist",
    "ask": "off",
    "askFallback": "deny",
    "autoAllowSkills": false
  },
  "agents": {
    "$DEFAULT_AGENT_ID": {
      "security": "allowlist",
      "ask": "off",
      "askFallback": "deny",
      "autoAllowSkills": false,
      "allowlist": [
        {
          "id": "openclaw-vps-host-action",
          "pattern": "${HOST_ACTION_SCRIPT}",
          "argPattern": "^(install-skill [a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)?|update-skills|refresh-config|sandbox-audit|doctor|restart-vps|as-openclaw .+|as-root .+|write-file-base64 [^|]+)$",
          "source": "operator-managed",
          "commandText": "${HOST_ACTION_SCRIPT} install-skill owner/name"
        }
      ]
    }
  }
}
EOF
  mv "$pending_tmp" "${STATE_DIR}/exec-approvals.pending.json" || return 1
  chown "$APP_USER:$APP_USER" "${STATE_DIR}/exec-approvals.pending.json"
  chmod 0600 "${STATE_DIR}/exec-approvals.pending.json"
}

# Call only for a fresh install ("fresh") or an explicit operator bootstrap.
# Reading exists through the CLI is essential: the active store may be SQLite.
seed_exec_allowlist() {
  local git_path gh_path snapshot exists pending pending_tmp
  git_path="$(resolve_verified_host_tool git)" || return 1
  gh_path="$(resolve_verified_host_tool gh)" || return 1
  snapshot="$(run_openclaw_local 'openclaw approvals get --json')" || { warn 'cannot read active approvals store'; return 1; }
  exists="$(printf '%s' "$snapshot" | jq -er 'if (.exists | type) == "boolean" and (.file | type) == "object" then (.exists | tostring) else error("unsupported approvals snapshot") end')" || return 1
  pending="$STATE_DIR/exec-approvals.pending.json"
  if [[ "$exists" == false && "${1:-}" == fresh ]]; then
    write_exec_approvals || return 1
    if ! run_openclaw_local "openclaw approvals set --file $(shell_quote "$pending")"; then
      warn "approvals import failed; pending artifact retained at $pending; service not started"
      return 1
    fi
  else
    # Diagnostic snapshot only: NEVER re-import defaults or an existing store.
    install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$STATE_DIR" || return 1
    pending_tmp="$(mktemp "$STATE_DIR/exec-approvals.XXXXXX")" || return 1
    chmod 0600 "$pending_tmp" || return 1
    printf '%s\n' "$snapshot" >"$pending_tmp" || return 1
    chown "$APP_USER:$APP_USER" "$pending_tmp" || return 1
    mv "$pending_tmp" "$pending" || return 1
  fi
  # The supported CLI performs idempotent additions without replacing policy.
  if ! run_openclaw_local "openclaw approvals allowlist add --agent '*' $(shell_quote "$git_path")" ||
     ! run_openclaw_local "openclaw approvals allowlist add --agent '*' $(shell_quote "$gh_path")"; then
    warn "approvals add failed; pending artifact retained at $pending; service not started"
    return 1
  fi
  rm -f "$pending"
}

ensure_workspace_host_action_notes() {
  local resolved_agents agent_id workspace sandbox_mode sandbox_backend
  resolved_agents="$(resolve_agent_state)" || return 1
  while IFS= read -r agent_id; do
    workspace="$(agent_workspace "$agent_id")" || return 1
    sandbox_mode="$(jq -r --arg id "$agent_id" ' .agents[] | select(.id == $id) | .sandbox.mode' <<<"$resolved_agents")"
    sandbox_backend="$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | if .sandbox.mode == "off" then "host" else (.sandbox.backend // "docker") end' <<<"$resolved_agents")"
    [[ -n "$workspace" ]] || continue
    install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$workspace"
    local tools_file="$workspace/TOOLS.md"
    if [[ ! -f "$tools_file" ]]; then
      printf '# TOOLS.md - Local Notes\n' >"$tools_file"
      chown "$APP_USER:$APP_USER" "$tools_file"
      chmod 0644 "$tools_file"
    fi
    if grep -q '^## VPS Host Actions$' "$tools_file"; then
      local tmp_tools
      tmp_tools="$(mktemp)"
      awk '
        /^## VPS Host Actions$/ { skip = 1; next }
        skip && /^## / { skip = 0 }
        !skip { print }
      ' "$tools_file" >"$tmp_tools"
      cat "$tmp_tools" >"$tools_file"
      rm -f "$tmp_tools"
    fi
    cat >>"$tools_file" <<EOF

## VPS Host Actions

Agent workspace: ${workspace}
Sandbox: ${sandbox_mode}; backend: ${sandbox_backend}. Host wrapper exec: gateway.

Gateway host execution uses an argument allowlist with prompting disabled.
Unmatched commands fail closed. Baseline grants pre-allow the verified \`git\`
and \`gh\` executables and the agent-scoped host-action wrapper below; existing
operator policy may be stricter. Additional entries require an operator action
with \`openclaw approvals allowlist\`. Report the missing capability to the
operator; do not attempt to bypass the allowlist or broaden your own permissions.

Approved host lifecycle actions are exposed through this exact wrapper:

\`\`\`bash
${HOST_ACTION_SCRIPT} sandbox-audit
${HOST_ACTION_SCRIPT} install-skill gog
${HOST_ACTION_SCRIPT} update-skills
${HOST_ACTION_SCRIPT} refresh-config
${HOST_ACTION_SCRIPT} doctor
${HOST_ACTION_SCRIPT} restart-vps
${HOST_ACTION_SCRIPT} as-openclaw gog auth list
${HOST_ACTION_SCRIPT} as-root apt-get update
${HOST_ACTION_SCRIPT} write-file-base64 /tmp/example.txt SGVsbG8= openclaw:openclaw 0600
\`\`\`

Important rules:

- Run the wrapper directly. Do not prefix it with \`sudo\`.
- Do not append shell redirection such as \`2>&1\`, pipes, \`&&\`, \`;\`, command substitution such as \`\$(...)\`, or extra shell syntax.
- Use \`${HOST_ACTION_SCRIPT} as-openclaw COMMAND...\` for VPS host commands. This runs as the \`${APP_USER}\` Linux user and can use passwordless \`sudo\` when a command needs root.
- Use \`${HOST_ACTION_SCRIPT} write-file-base64 PATH BASE64 [OWNER] [MODE]\` to write file content without redirects, heredocs, pipes, or shell quoting problems.
- Use \`${HOST_ACTION_SCRIPT} as-root COMMAND...\` only when the user explicitly asks for root-level VPS host changes, such as installing system packages.
- Install developer tooling with commands suitable for this Unix-like machine. Download scripts to a file and inspect them before running them.
- Use \`${HOST_ACTION_SCRIPT} restart-vps\` when the user explicitly asks you to restart the VPS. Warn that the chat may go offline briefly, then run only that command.
- Use ClawHub skill slugs, for example \`gog\`, not GitHub-style \`steipete/gog\` unless the user explicitly gives a ClawHub slug containing \`/\`.
- If the wrapper reports that a skill already exists, treat the host skill installation as complete and run \`refresh-config\` or \`sandbox-audit\` as needed.
EOF
    chown "$APP_USER:$APP_USER" "$tools_file"
    chmod 0644 "$tools_file"
  done < <(jq -r '.agents[]?.id' <<<"$resolved_agents")
}

write_maintenance_helper() {
  cat >"$MAINTENANCE_HELPER_PATH" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"
LOG_DIR="${LOG_DIR}"
SERVICE="${OPENCLAW_SERVICE}"
GROUPS_FILE="${GROUPS_FILE}"
SERVE_ENABLED_FILE="${SERVE_ENABLED_FILE}"
TAILSCALE_SERVE_TARGET="${TAILSCALE_SERVE_TARGET}"
mkdir -p "\$LOG_DIR"
log_file="\$LOG_DIR/maintenance-\$(date -u +%Y%m%dT%H%M%SZ).log"
run_as_user() {
  sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; \$*"
}
user_systemctl() {
  uid="\$(id -u "\$APP_USER")"
  runuser -u "\$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/\$uid" systemctl --user "\$@"
}
{
  echo "maintenance started \$(date -u --iso-8601=seconds)"
  if [[ -f "\$SERVE_ENABLED_FILE" ]]; then
    if tailscale serve --bg "\$TAILSCALE_SERVE_TARGET" >/dev/null 2>&1; then
      echo "Tailscale Serve reasserted"
    else
      echo "Tailscale Serve reassert failed"
    fi
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get -y upgrade
  apt-get -y autoremove
  apt-get -y autoclean
  while IFS= read -r container; do
    [[ -n "\$container" ]] || continue
    incus exec "\$container" -- bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get -y upgrade; apt-get -y autoremove; apt-get -y autoclean" || true
  done < <(jq -r '.groups[]?.container' "\$GROUPS_FILE")
  run_as_user "npm update -g opencode-ai"
  run_as_user "openclaw update --dry-run" || true
  run_as_user "openclaw update --yes" || run_as_user "npm update -g openclaw"
  if [[ -x /root/openclaw-vps.sh ]]; then
    /root/openclaw-vps.sh refresh-config || true
  fi
  run_as_user "openclaw doctor" || true
  /usr/local/sbin/openclaw-vps-sandbox-audit || true
  run_as_user "openclaw security audit" || true
  /usr/local/sbin/openclaw-vps-backup || true
  while IFS= read -r container; do
    [[ -n "\$container" ]] || continue
    incus restart "\$container" || true
  done < <(jq -r '.groups[]?.container' "\$GROUPS_FILE")
  user_systemctl restart "\$SERVICE"
  user_systemctl --no-pager --full status "\$SERVICE" || true
  echo "maintenance finished \$(date -u --iso-8601=seconds)"
} 2>&1 | tee -a "\$log_file"
EOF
  chmod 0755 "$MAINTENANCE_HELPER_PATH"
}

write_helper_scripts() {
  log "writing maintenance, backup, status, doctor, and log helper scripts"
  write_sandbox_dependency_audit
  write_host_action_helper
  ensure_workspace_host_action_notes
  write_maintenance_helper
  cat >/usr/local/sbin/openclaw-vps-backup <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
BACKUP_DIR="${BACKUP_DIR}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"
LOG_DIR="${LOG_DIR}"
GROUPS_FILE="${GROUPS_FILE}"
mkdir -p "\$BACKUP_DIR" "\$LOG_DIR"
chown "\$APP_USER:\$APP_USER" "\$BACKUP_DIR"
log_file="\$LOG_DIR/backup-\$(date -u +%Y%m%dT%H%M%SZ).log"
run_as_user() {
  sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; \$*"
}
{
  echo "backup started \$(date -u --iso-8601=seconds)"
  find /home/openclaw/.openclaw/chrome-profile -maxdepth 1 -type l -name "Singleton*" -delete 2>/dev/null || true
  run_as_user "openclaw backup create --verify --output '\$BACKUP_DIR'"
  while IFS= read -r container; do
    [[ -n "\$container" ]] || continue
    incus_backup="\$BACKUP_DIR/incus-\$container-\$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
    incus export "\$container" "\$incus_backup" --instance-only
  done < <(jq -r '.groups[]?.container' "\$GROUPS_FILE")
  find "\$BACKUP_DIR" -type f -name '*openclaw-backup.tar.gz' -mtime +30 -delete
  find "\$BACKUP_DIR" -type f -name 'incus-*.tar.gz' -mtime +14 -delete
  echo "backup finished \$(date -u --iso-8601=seconds)"
} 2>&1 | tee -a "\$log_file"
EOF
  chmod 0755 /usr/local/sbin/openclaw-vps-backup

  cat >/usr/local/sbin/openclaw-vps-doctor <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"
GROUPS_FILE="${GROUPS_FILE}"
SANDBOX_SSH_KEY="${SANDBOX_SSH_KEY}"
SANDBOX_KNOWN_HOSTS_DIR="${SANDBOX_KNOWN_HOSTS_DIR}"
run_as_user() {
  sudo -Hiu "\$APP_USER" bash -lc "set -a; . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; \$*"
}
/usr/local/sbin/openclaw-vps-sandbox-audit || true
while IFS= read -r row; do
  group_id="\${row%%:*}"
  rest="\${row#*:}"
  container="\${rest%%:*}"
  port="\${rest#*:}"
  known_hosts="\$SANDBOX_KNOWN_HOSTS_DIR/\${group_id}_known_hosts"
  incus info "\$container"
  incus exec "\$container" -- timedatectl
  sudo -Hiu "\$APP_USER" ssh -i "\$SANDBOX_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="\$known_hosts" -p "\$port" "\$APP_USER@127.0.0.1" "pwd" >/dev/null
done < <(jq -r '.groups[]? | "\(.id):\(.container):\(.sshPort)"' "\$GROUPS_FILE")
run_as_user "openclaw doctor"
run_as_user "openclaw sandbox explain" || true
run_as_user "openclaw security audit" || true
EOF
  chmod 0755 /usr/local/sbin/openclaw-vps-doctor

  cat >/usr/local/sbin/openclaw-vps-status <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
USER_ENV_FILE="${USER_ENV_FILE}"
USER_BIN_DIR="${USER_BIN_DIR}"
SERVICE="${OPENCLAW_SERVICE}"
GROUPS_FILE="${GROUPS_FILE}"
run_as_user() {
  sudo -Hiu "\$APP_USER" bash -lc "set -a; [[ -r '\$USER_ENV_FILE' ]] && . '\$USER_ENV_FILE'; set +a; export PATH='\$USER_BIN_DIR:/usr/local/bin:/usr/bin:/bin'; \$*"
}
user_systemctl() {
  uid="\$(id -u "\$APP_USER")"
  runuser -u "\$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/\$uid" systemctl --user "\$@"
}
echo "== system =="
hostnamectl || true
echo
echo "== tailscale =="
tailscale status || true
echo
echo "== firewall =="
ufw status verbose || true
echo
echo "== openclaw-vps groups =="
jq . "\$GROUPS_FILE" || true
echo
echo "== openclaw-vps agents =="
jq . "${AGENTS_FILE}" || true
echo
echo "== agent execution environments =="
/usr/local/sbin/openclaw-vps-sandbox-audit || true
echo
echo "== incus sandboxes =="
while IFS= read -r container; do
  [[ -n "\$container" ]] || continue
  incus info "\$container" || true
  incus config device show "\$container" || true
  incus exec "\$container" -- timedatectl || true
done < <(jq -r '.groups[]?.container' "\$GROUPS_FILE")
echo
echo "== sandbox ssh =="
jq -r '.groups[]? | "\(.id):\(.sshPort)"' "\$GROUPS_FILE" | while IFS=: read -r group_id port; do
  ss -ltn 2>/dev/null | grep -q ":\$port " && echo "\$group_id 127.0.0.1:\$port listening" || echo "\$group_id 127.0.0.1:\$port not detected"
done
echo
echo "== fail2ban =="
fail2ban-client status sshd || true
echo
echo "== node/npm =="
node --version || true
npm --version || true
echo
echo "== openclaw/opencode =="
run_as_user "openclaw --version" || true
run_as_user "opencode --version" || true
echo
echo "== openclaw service =="
user_systemctl --no-pager --full status "\$SERVICE" || true
EOF
  chmod 0755 /usr/local/sbin/openclaw-vps-status

  cat >/usr/local/sbin/openclaw-vps-logs <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="${APP_USER}"
SERVICE="${OPENCLAW_SERVICE}"
uid="\$(id -u "\$APP_USER")"
exec runuser -u "\$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/\$uid" journalctl --user -u "\$SERVICE" -f
EOF
  chmod 0755 /usr/local/sbin/openclaw-vps-logs
}

write_systemd_timers() {
  log "writing systemd maintenance and backup timers"
  cat >/etc/systemd/system/openclaw-vps-maintenance.service <<'EOF'
[Unit]
Description=OpenClaw VPS weekly maintenance

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openclaw-vps-maintenance
EOF

  cat >/etc/systemd/system/openclaw-vps-maintenance.timer <<'EOF'
[Unit]
Description=Run OpenClaw VPS maintenance weekly

[Timer]
OnCalendar=Sun 04:00
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF

  cat >/etc/systemd/system/openclaw-vps-backup.service <<'EOF'
[Unit]
Description=OpenClaw VPS daily backup

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openclaw-vps-backup
EOF

  cat >/etc/systemd/system/openclaw-vps-backup.timer <<'EOF'
[Unit]
Description=Run OpenClaw VPS backup daily

[Timer]
OnCalendar=*-*-* 03:15
Persistent=true
RandomizedDelaySec=20m

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now openclaw-vps-maintenance.timer openclaw-vps-backup.timer
}

ensure_tailscale_connected() {
  command -v tailscale >/dev/null 2>&1 || fail "tailscale is not installed"
  systemctl is-active --quiet tailscaled.service || fail "tailscaled is not active"
  local ts_ip
  ts_ip="$(tailscale ip -4 2>/dev/null || true)"
  [[ -n "$ts_ip" ]] || fail "Tailscale has no IPv4 address; refusing to lock down public access"
  ip link show "$TAILSCALE_IFACE" >/dev/null 2>&1 || fail "${TAILSCALE_IFACE} interface not found"
}

gateway_is_listening() {
  curl --silent --show-error --max-time 3 --output /dev/null "$TAILSCALE_SERVE_TARGET"
}

tailnet_dns_name() {
  need_command jq
  local dns_name
  dns_name="$(tailscale status --json | jq -r '.Self.DNSName // empty')"
  dns_name="${dns_name%.}"
  [[ -n "$dns_name" ]] || fail "Tailscale status did not report the self node DNS name"
  printf '%s' "$dns_name"
}

cmd_serve() {
  require_root
  need_command curl
  need_command loginctl
  ensure_tailscale_connected
  loginctl enable-linger "$APP_USER"
  if ! gateway_is_listening; then
    fail "OpenClaw gateway is not listening at ${TAILSCALE_SERVE_TARGET}; run './openclaw-vps.sh status' and inspect ${OPENCLAW_SERVICE}"
  fi

  install -d -m 0750 "$STATE_DIR"
  local serve_output dns_name
  if ! serve_output="$(tailscale serve --bg "$TAILSCALE_SERVE_TARGET" 2>&1)"; then
    printf '%s\n' "$serve_output" >&2
    if grep -Eiq 'magicdns|https|certificate|cert' <<<"$serve_output"; then
      printf '[openclaw-vps] action: enable both MagicDNS and HTTPS Certificates in the Tailscale admin console, then rerun ./openclaw-vps.sh serve\n' >&2
    fi
    fail "Tailscale Serve could not be enabled"
  fi
  [[ -z "$serve_output" ]] || printf '%s\n' "$serve_output"
  touch "$SERVE_ENABLED_FILE"
  chmod 0640 "$SERVE_ENABLED_FILE"
  dns_name="$(tailnet_dns_name)"
  log "OpenClaw dashboard: https://${dns_name}"
  log "gateway authentication still applies; tailnet-only, nothing is exposed to the public internet."
}

cmd_serve_off() {
  require_root
  need_command tailscale
  rm -f "$SERVE_ENABLED_FILE"
  local serve_output
  if ! serve_output="$(tailscale serve reset 2>&1)"; then
    printf '%s\n' "$serve_output" >&2
    fail "Tailscale Serve reset failed"
  fi
  [[ -z "$serve_output" ]] || printf '%s\n' "$serve_output"
  log "OpenClaw dashboard Serve disabled; enablement flag cleared."
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
  ufw allow in on incusbr0
  ufw route allow in on incusbr0
  if [[ "$KEEP_PUBLIC_SSH" == "1" ]]; then
    warn "keeping public SSH open because --keep-public-ssh was provided"
    ufw allow OpenSSH
  fi
  ufw --force enable
  ufw status verbose
}

install_all() {
  require_initial_agent_identity
  refuse_existing_managed_state
  preflight
  apt_install_hardening_first
  configure_ssh_hardening
  configure_fail2ban
  configure_unattended_upgrades
  configure_host_timezone

  log "baseline hardening is active; prompting for setup credentials"
  local tailscale_auth_key model_api_key telegram_bot_token telegram_allow_from
  tailscale_auth_key="${TAILSCALE_AUTH_KEY:-}"
  model_api_key="$(prompt_secret MODEL_API_KEY 'Model provider API key' required)"
  telegram_bot_token="$(prompt_secret TELEGRAM_BOT_TOKEN 'Telegram bot token' optional)"
  telegram_allow_from="${TELEGRAM_ALLOW_FROM:-}"
  if [[ -n "$telegram_bot_token" && -z "$telegram_allow_from" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist (leave empty for pairing flow): ' telegram_allow_from
  fi

  ensure_app_user
  install_tailscale
  tailscale_up "$tailscale_auth_key"
  install_node
  install_incus
  install_openclaw_and_opencode
  ensure_git_gh_installed || return 1
  write_user_env "$MODEL_PROVIDER" "$MODEL_BASE_URL" "$model_api_key" "$MODEL_ID" "$MODEL_CATALOG" "$telegram_bot_token"
  ensure_user_shell_sources_env
  ensure_group "$DEFAULT_GROUP_ID"
  if ! agent_exists "$DEFAULT_AGENT_ID"; then
    ensure_agent "$DEFAULT_AGENT_ID" "$DEFAULT_GROUP_ID" "$telegram_bot_token" "$telegram_allow_from" "$OPENCLAW_INITIAL_AGENT_LABEL" true
  fi
  regenerate_openclaw_config
  seed_provider_auth
  write_opencode_config
  seed_exec_allowlist fresh || return 1
  install_user_systemd_service
  write_helper_scripts
  write_systemd_timers

  log "install complete"
  log "run './openclaw-vps.sh status' to inspect the system"
  log "run 'sudo -iu ${APP_USER}' then 'opencode' to use OpenCode for recovery work"
  if [[ -n "$telegram_bot_token" && -z "$telegram_allow_from" ]]; then
    log "Telegram pairing flow: DM your bot, then run as ${APP_USER}: openclaw pairing list telegram && openclaw pairing approve telegram <CODE>"
  fi

  if [[ "$REQUEST_LOCKDOWN" == "1" ]]; then
    lockdown_firewall
  else
    warn "public firewall lockdown was not applied. Run './openclaw-vps.sh lockdown' after confirming Tailscale access."
  fi
}

cmd_status() {
  require_root
  if [[ -x /usr/local/sbin/openclaw-vps-status ]]; then
    /usr/local/sbin/openclaw-vps-status
  else
    warn "helper not installed yet; showing minimal status"
    systemctl status fail2ban --no-pager || true
    tailscale status || true
    ufw status verbose || true
  fi
}

restart_openclaw_gateway() {
  local uid
  uid="$(id -u "$APP_USER")"
  runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user restart "$OPENCLAW_SERVICE"
}

cmd_add_group() {
  require_root
  local group_id="${1:-}"
  [[ -n "$group_id" ]] || fail "add-group requires GROUP"
  validate_managed_id "$group_id"
  need_command jq
  need_command incus
  resolve_agent_state >/dev/null || return 1
  ensure_app_user
  ensure_group "$group_id"
  regenerate_openclaw_config
  write_helper_scripts
  log "group ${group_id} is ready"
}

cmd_add_agent() {
  require_root
  local agent_id="${1:-}"
  [[ -n "$agent_id" ]] || fail "add-agent requires AGENT"
  shift || true

  local group_id=""
  while (($#)); do
    case "$1" in
      --group)
        [[ -n "${2:-}" ]] || fail "--group requires a value"
        group_id="$2"
        shift 2
        ;;
      --sandbox)
        [[ -n "${2:-}" ]] || fail "--sandbox requires a JSON policy object"
        OPENCLAW_AGENT_SANDBOX="$2"
        shift 2
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      *)
        fail "unknown add-agent option: $1"
        ;;
    esac
  done

  [[ -n "$group_id" ]] || fail "add-agent requires --group GROUP"
  validate_managed_id "$agent_id"
  validate_managed_id "$group_id"
  need_command jq
  need_command incus
  resolve_agent_state "$agent_id" >/dev/null || return 1
  ensure_app_user
  if ! group_exists "$group_id"; then
    if confirm "Isolation group ${group_id} does not exist. Create it now?"; then
      ensure_group "$group_id"
    else
      fail "isolation group not found: ${group_id}"
    fi
  fi
  if agent_exists "$agent_id"; then
    fail "agent already exists: ${agent_id}"
  fi

  local telegram_bot_token telegram_allow_from
  telegram_bot_token="$(prompt_secret OPENCLAW_AGENT_TELEGRAM_BOT_TOKEN 'Telegram bot token for this agent' required)"
  telegram_allow_from="${OPENCLAW_AGENT_TELEGRAM_ALLOW_FROM:-}"
  if [[ -z "$telegram_allow_from" ]]; then
    read -r -p 'Numeric Telegram user ID allowlist for this agent (leave empty for pairing flow): ' telegram_allow_from
  fi

  ensure_agent "$agent_id" "$group_id" "$telegram_bot_token" "$telegram_allow_from" "$agent_id" false
  regenerate_openclaw_config
  write_opencode_config
  write_helper_scripts
  restart_openclaw_gateway
  log "agent ${agent_id} is ready"
  if [[ -z "$telegram_allow_from" ]]; then
    log "Telegram pairing flow: DM this agent's bot, then run as ${APP_USER}: openclaw pairing list telegram && openclaw pairing approve telegram <CODE>"
  fi
}

cmd_list() {
  require_root
  ensure_app_user
  ensure_state_files
  printf '== groups ==\n'
  jq . "$GROUPS_FILE"
  printf '\n== agents ==\n'
  jq . "$AGENTS_FILE"
}

cmd_refresh_config() {
  require_root
  need_command jq
  need_command incus
  resolve_agent_state >/dev/null || return 1
  ensure_app_user
  ensure_state_files
  resolve_openclaw_timezone
  set_user_env_value OPENCLAW_TIMEZONE "$OPENCLAW_TIMEZONE"
  set_user_env_value TZ "$OPENCLAW_TIMEZONE"
  while IFS= read -r group_id; do
    [[ -n "$group_id" ]] || continue
    ensure_group "$group_id"
  done < <(jq -r '.groups[]?.id' "$GROUPS_FILE")
  regenerate_openclaw_config
  seed_provider_auth
  write_opencode_config
  write_helper_scripts
  restart_openclaw_gateway
  log "OpenClaw and OpenCode config refreshed"
}

cmd_backup() {
  require_root
  [[ -x /usr/local/sbin/openclaw-vps-backup ]] || fail "backup helper not installed; run install first"
  /usr/local/sbin/openclaw-vps-backup
}

cmd_maintenance() {
  require_root
  [[ -x "$MAINTENANCE_HELPER_PATH" ]] || fail "maintenance helper not installed; run install first"
  "$MAINTENANCE_HELPER_PATH"
}

cmd_logs() {
  require_root
  [[ -x /usr/local/sbin/openclaw-vps-logs ]] || fail "logs helper not installed; run install first"
  /usr/local/sbin/openclaw-vps-logs
}

cmd_doctor() {
  require_root
  [[ -x /usr/local/sbin/openclaw-vps-doctor ]] || fail "doctor helper not installed; run install first"
  /usr/local/sbin/openclaw-vps-doctor
}

parse_options() {
  while (($#)); do
    case "$1" in
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
      cmd_add_group "$@"
      ;;
    add-agent)
      cmd_add_agent "$@"
      ;;
    list)
      cmd_list
      ;;
    refresh-config)
      cmd_refresh_config
      ;;
    github-token-stage)
      cmd_github_token_stage "$@"
      ;;
    github-token-discard)
      cmd_github_token_discard "$@"
      ;;
    github-bootstrap)
      cmd_github_bootstrap "$@"
      ;;
    serve)
      cmd_serve
      ;;
    serve-off)
      cmd_serve_off
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
