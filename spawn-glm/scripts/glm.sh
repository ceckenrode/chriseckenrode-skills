#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'Usage: bash glm.sh --project DIR --prompt-file FILE [--model MODEL] [--variant EFFORT] [--session ID] [--agent ROLE] [--title TITLE] [--permissions full|configured]'
}

fail() { printf 'glm.sh: %s\n' "$1" >&2; exit 2; }

project_path=''
brief_path=''
model_id='zai-coding-plan/glm-5.3'
permissions='full'
extra_args=(--format json)
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project|--prompt-file|--model|--variant|--session|--agent|--title|--permissions)
      (($# >= 2)) && [[ -n "$2" ]] || fail "missing value for $1"
      case "$1" in
        --project) project_path="$2" ;;
        --prompt-file) brief_path="$2" ;;
        --model) model_id="$2" ;;
        --permissions) permissions="$2" ;;
        *) extra_args+=("$1" "$2") ;;
      esac
      shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -d "$project_path" ]] || fail '--project must name an existing directory'
[[ -f "$brief_path" && -r "$brief_path" && -s "$brief_path" ]] || fail '--prompt-file must name a readable, nonempty file'
command -v opencode >/dev/null 2>&1 || fail 'opencode is not installed or not on PATH'
project_path=$(cd -- "$project_path" && pwd -P)
[[ "$model_id" == */* ]] || model_id="zai-coding-plan/$model_id"
brief_text=$(< "$brief_path")
[[ -n "$brief_text" ]] || fail 'prompt is empty'

case "$permissions" in
  full) export OPENCODE_PERMISSION='{"*":"allow"}'; extra_args+=(--auto) ;;
  configured) ;;
  *) fail '--permissions must be full or configured' ;;
esac

exec opencode run --dir "$project_path" --model "$model_id" \
  "${extra_args[@]}" -- "$brief_text"
