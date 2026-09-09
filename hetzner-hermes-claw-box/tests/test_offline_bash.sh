#!/bin/bash
set -Eeuo pipefail

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(CDPATH= cd -- "$test_dir/.." && pwd)
test_bash=${BOXSKILL_TEST_BASH:-bash}
canonical_root=${BOXSKILL_CANONICAL_ROOT-}
working_root=${BOXSKILL_WORKING_ROOT-}

if [ -d "$root_dir/scripts" ]; then
    scripts_dir=$root_dir/scripts
elif [ -d "$root_dir/.agents/skills/hetzner-agent-box/scripts" ]; then
    scripts_dir=$root_dir/.agents/skills/hetzner-agent-box/scripts
else
    echo "could not find scripts distribution relative to $test_dir" >&2
    exit 1
fi

for script_name in \
    hermes-hetzner.sh \
    hermes-vps.sh \
    openclaw-hetzner.sh \
    openclaw-vps.sh \
    setup-agent-box.sh \
    agent-box-manage.sh
do
    script_path=$scripts_dir/$script_name
    if [ ! -f "$script_path" ]; then
        echo "missing distributed script: $script_path" >&2
        exit 1
    fi
    /bin/bash -n "$script_path"
done
/bin/bash -n "$0"

cd "$root_dir"
BOXSKILL_TEST_BASH="$test_bash" \
BOXSKILL_CANONICAL_ROOT="$canonical_root" \
BOXSKILL_WORKING_ROOT="$working_root" \
python3 -B -m unittest discover -s tests -k envfix -v
