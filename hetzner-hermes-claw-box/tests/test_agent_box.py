"""Offline contract tests: all API, SSH, key generation and provisioning are stubbed."""
import json
import pty
import select
import time
import shlex
import termios
import fcntl
import hashlib
import io
import fnmatch
import tarfile
import sys
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def _resolve_scripts_dir(test_file=__file__):
    """Find the distribution paired with this test file in either layout."""
    test_root = Path(test_file).resolve().parents[1]
    candidates = (
        test_root / 'scripts',
        test_root / '.agents/skills/hetzner-agent-box/scripts',
    )
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    locations = ', '.join(str(candidate) for candidate in candidates)
    raise RuntimeError(f'could not find scripts distribution; checked: {locations}')


SCRIPTS = _resolve_scripts_dir()

_CROSS_REPO_PAIRS = (
    *tuple((f'scripts/{name}', f'.agents/skills/hetzner-agent-box/scripts/{name}')
           for name in ('hermes-hetzner.sh', 'hermes-vps.sh', 'openclaw-hetzner.sh',
                        'openclaw-vps.sh', 'setup-agent-box.sh', 'agent-box-manage.sh')),
    *tuple((name, name) for name in ('hermes-hetzner.sh', 'hermes-vps.sh',
                                    'openclaw-hetzner.sh', 'openclaw-vps.sh')),
    ('SKILL.md', '.agents/skills/hetzner-agent-box/SKILL.md'),
    ('AGENTS.md', '.agents/skills/hetzner-agent-box/AGENTS.md'),
    ('.gitignore', '.agents/skills/hetzner-agent-box/.gitignore'),
    ('agents/openai.yaml', '.agents/skills/hetzner-agent-box/agents/openai.yaml'),
    ('README.md', '.agents/skills/hetzner-agent-box/README.md'),
    ('boxes.example.json', '.agents/skills/hetzner-agent-box/boxes.example.json'),
    ('README.md', 'README.md'),
    ('boxes.example.json', 'boxes.example.json'),
    ('references/troubleshooting.md', '.agents/skills/hetzner-agent-box/references/troubleshooting.md'),
    ('references/github-bootstrap.md', '.agents/skills/hetzner-agent-box/references/github-bootstrap.md'),
    ('references/workspace-recovery.md', '.agents/skills/hetzner-agent-box/references/workspace-recovery.md'),
    ('references/troubleshooting.md', 'references/troubleshooting.md'),
    ('references/github-bootstrap.md', 'references/github-bootstrap.md'),
    ('references/workspace-recovery.md', 'references/workspace-recovery.md'),
    ('docs/agents/known-issues-and-improvements.md',
     '.agents/skills/hetzner-agent-box/docs/agents/known-issues-and-improvements.md'),
    ('docs/agents/known-issues-and-improvements.md', 'docs/agents/known-issues-and-improvements.md'),
    ('tests/test_agent_box.py', '.agents/skills/hetzner-agent-box/tests/test_agent_box.py'),
    ('tests/test_offline_bash.sh', '.agents/skills/hetzner-agent-box/tests/test_offline_bash.sh'),
    ('tests/test_agent_box.py', 'tests/test_agent_box.py'),
    ('tests/test_offline_bash.sh', 'tests/test_offline_bash.sh'),
)


def test_bash():
    return os.environ.get('BOXSKILL_TEST_BASH', 'bash')


def shell_command(*args):
    return [test_bash(), *args]


def cross_repo_roots(environ=None):
    environ = os.environ if environ is None else environ
    canonical = environ.get('BOXSKILL_CANONICAL_ROOT', '').strip()
    working = environ.get('BOXSKILL_WORKING_ROOT', '').strip()
    if bool(canonical) != bool(working):
        raise RuntimeError(
            'BOXSKILL_CANONICAL_ROOT and BOXSKILL_WORKING_ROOT must be set together'
        )
    if not canonical:
        return None
    return Path(canonical).resolve(), Path(working).resolve()


def _cross_repo_mismatches(canonical, working):
    mismatches = []
    for canonical_relative, working_relative in _CROSS_REPO_PAIRS:
        canonical_path = canonical / canonical_relative
        working_path = working / working_relative
        if not canonical_path.is_file():
            mismatches.append(f'missing canonical: {canonical_path}')
        elif not working_path.is_file():
            mismatches.append(f'missing working: {working_path}')
        elif canonical_path.read_bytes() != working_path.read_bytes():
            mismatches.append(f'content mismatch: {canonical_path} != {working_path}')
    return mismatches


def _enforce_cross_repo_parity():
    roots = cross_repo_roots()
    if roots is None:
        return
    mismatches = _cross_repo_mismatches(*roots)
    if mismatches:
        raise RuntimeError('cross-repo parity check failed:\n' + '\n'.join(mismatches))


_enforce_cross_repo_parity()


class AgentBoxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='agent-box-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / 'project'
        self.project.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.home = self.base / 'home'
        (self.home / '.ssh').mkdir(parents=True)
        self.key = self.home / '.ssh/agentbox_hetzner_ed25519'
        self.key.write_text('TEST PRIVATE KEY PLACEHOLDER')
        Path(str(self.key) + '.pub').write_text('TEST PUBLIC KEY PLACEHOLDER')
        self.calls = self.base / 'calls'
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:{os.environ["PATH"]}', CALLS=str(self.calls))
        for name in ('ENV_FILE', 'ENV_EXAMPLE_FILE', 'CREDENTIALS_FILE', 'PROJECT_DIR', 'DEFAULT_KEY_PATH', 'SSH_PUBLIC_KEY_PATH', 'HETZNER_SERVER_TYPE', 'HETZNER_LOCATION'):
            self.env.pop(name, None)
        self.stub(self.bin / 'curl', r'''
printf "curl\n" >> "$CALLS"
header_file=""
while (($#)); do
    if [[ "$1" == "-H" ]]; then
        header_file="${2#@}"
        [[ "${2:-}" == *test-token* ]] && printf "TOKEN_ON_ARG\n" >> "$CALLS"
        shift
    elif [[ "$1" == *test-token* ]]; then
        printf "TOKEN_ON_ARG\n" >> "$CALLS"
    fi
    shift
done
if [[ -n "$header_file" ]]; then
    cat "$header_file" > "$CALLS.header"
fi
if [[ "${CURL_EXIT:-0}" != 0 ]]; then
    exit "$CURL_EXIT"
fi
cat <<'JSON'
{"server_types":[
  {"name":"cx23","locations":["fsn1","nbg1","hel1"]},
  {"name":"cax11","locations":["nbg1","hel1"]},
  {"name":"cx33","locations":["fsn1","nbg1","hel1"]}
]}
JSON
''')
        self.stub(self.bin / 'git', 'exit 1\n')
        self.stub(self.bin / 'ssh', 'printf "%s\\n" "$@" > "$CALLS"\nexit "${REMOTE_EXIT:-0}"\n')
        self.stub(self.bin / 'ssh-keygen', 'printf "%s\\n" "$@" > "$CALLS"\n')

    def stub(self, path, body):
        interpreter = test_bash()
        shebang = f'#!{interpreter}' if interpreter.startswith('/') else f'#!/usr/bin/env {interpreter}'
        path.write_text(shebang + '\nset -Eeuo pipefail\n' + body)
        path.chmod(0o755)

    def run_script(self, name, *args, input='', ok=True):
        result = subprocess.run(shell_command(str(SCRIPTS / name), *args), cwd=self.project,
                                env=self.env, input=input, text=True, capture_output=True, timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def setup(self, runtime='Hermes', bot='test-bot', allow='12345', extra='', env_options=(),
              server_type='', location='', key_path='', ok=True, initial_id='dorian',
              initial_label='Dorian', github='n'):
        # Fake token is only consumed by the curl executable installed above.
        identity = [initial_id, initial_label, github] if runtime.lower() == 'openclaw' else []
        values = [runtime, *identity, server_type, location, 'test-token', '', 'testai', 'https://api.testai.example/v1', 'test-model-key-1234567890', 'testai/model-1', bot,
                  allow, '', key_path, 'pass$`word']
        return self.run_script('setup-agent-box.sh', *env_options, input='\n'.join(values) + '\n' + extra, ok=ok)

    def register(self, runtime='hermes', box='test-box', server_id='123', **kwargs):
        ok = kwargs.pop('ok', True)
        if runtime == 'openclaw':
            kwargs.setdefault('agent', 'main')
            kwargs.setdefault('group', 'main')
        args = ['register', '--runtime', runtime, '--box', box, '--server-id', server_id,
                '--server-type', 'cx23', '--location', 'fsn1', '--public-ip', '192.0.2.1',
                '--tailscale-ip', '100.64.0.10', '--ssh-key', str(self.key)]
        for option in ('agent', 'group'):
            if option in kwargs:
                args.extend(['--' + option, kwargs[option]])
        return self.run_script('agent-box-manage.sh', *args, ok=ok)

    def state(self):
        return json.loads((self.project / 'boxes.json').read_text())

    def wrapper(self, runtime):
        self.stub(self.project / f'{runtime}-hetzner.sh', 'printf "%s\\n" "$@" > "$CALLS"\nexit "${REMOTE_EXIT:-0}"\n')

    def run_vps_functions(self, command, state=None, gateway=True, tailscale_exit=0,
                          tailscale_error='', extra_env=None, input_text=''):
        """Run the VPS script's function definitions without invoking main or requiring root."""
        self.stub(self.bin / 'id', r'''
if [[ "${1:-}" == "-u" ]]; then
    printf '0\n'
else
    /usr/bin/id "$@"
fi
''')
        self.stub(self.bin / 'systemctl', '[[ "${1:-}" == "is-active" ]] && exit 0\nexit 0\n')
        self.stub(self.bin / 'ip', 'exit 0\n')
        self.stub(self.bin / 'loginctl', 'printf "loginctl %s\\n" "$*" >> "$CALLS"\n')
        self.stub(self.bin / 'curl', r'''
for arg in "$@"; do
    if [[ "$arg" == */models ]]; then
        if [[ -n "${MODELS_JSON_FILE:-}" && -r "$MODELS_JSON_FILE" ]]; then
            cat "$MODELS_JSON_FILE"
        fi
        exit 0
    fi
done
if [[ "${CURL_GATEWAY_OK:-1}" != 1 ]]; then
    printf 'gateway is unavailable\n' >&2
    exit 7
fi
exit 0
''')
        self.stub(self.bin / 'tailscale', r'''
printf 'tailscale %s\n' "$*" >> "$CALLS"
case "${1:-}" in
    ip) printf '100.64.0.10\n' ;;
    status)
        cat <<'JSON'
{"Self":{"DNSName":"openclaw-box.tail1234.ts.net."}}
JSON
        ;;
    serve)
        if [[ "${TAILSCALE_EXIT:-0}" != 0 ]]; then
            printf '%s\n' "${TAILSCALE_ERROR:-serve failed}" >&2
            exit "$TAILSCALE_EXIT"
        fi
        ;;
    *) ;;
esac
''')
        source = (SCRIPTS / 'openclaw-vps.sh').read_text().rsplit('\nmain "$@"', 1)[0]
        state_dir = Path(state or (self.base / 'openclaw-state'))
        env = dict(self.env, CURL_GATEWAY_OK='1' if gateway else '0',
                   TAILSCALE_EXIT=str(tailscale_exit), TAILSCALE_ERROR=tailscale_error,
                   MODEL_PROVIDER='testai', MODEL_BASE_URL='https://api.testai.example/v1',
                   MODEL_API_KEY='test-model-key', MODEL_ID='testai/model-1')
        if extra_env:
            env.update(extra_env)
        local_config_stub = ''
        if not (extra_env or {}).get('ENVFIX_REAL_EXEC'):
            # Older behavior tests still run the REAL policy selection; only local
            # schema/validation CLI I/O is stubbed. Other CLI calls keep their fixtures.
            fixture = {'properties': {'tools': {'properties': {'exec': {'properties': {
                'security': {'enum': ['deny', 'allowlist', 'full']},
                'ask': {'enum': ['off', 'on-miss', 'always']},
                'strictInlineEval': {'type': 'boolean'}}}}}}}
            local_config_stub = r'''
eval "$(declare -f run_openclaw_local | sed '1s/run_openclaw_local/envfix_real_openclaw_local/')"
run_openclaw_local() {
  case "$1" in
    'openclaw config schema --json') printf '%s\n' 'SCHEMA_FIXTURE' ;;
    *' openclaw config validate --json') return 0 ;;
    *) envfix_real_openclaw_local "$1" ;;
  esac
}
'''.replace('SCHEMA_FIXTURE', json.dumps(fixture))
        overrides = f'''
STATE_DIR={str(state_dir)!r}
GROUPS_FILE="$STATE_DIR/groups.json"
AGENTS_FILE="$STATE_DIR/agents.json"
OPENCLAW_CONFIG_DIR="$STATE_DIR/config"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"
USER_CONFIG_DIR="$STATE_DIR/user-config"
USER_ENV_FILE="$USER_CONFIG_DIR/env"
USER_BIN_DIR={str(self.bin)!r}
SERVE_ENABLED_FILE="$STATE_DIR/serve.enabled"
MAINTENANCE_HELPER_PATH={str(self.base / 'maintenance-helper')!r}
LOG_DIR={str(self.base / 'maintenance-logs')!r}
APP_USER=openclaw
TAILSCALE_SERVE_TARGET=http://127.0.0.1:18789
{local_config_stub}
{command}
'''
        return subprocess.run(shell_command('-c', source + overrides), cwd=self.project,
                              env=env, input=input_text, text=True, capture_output=True,
                              timeout=15)

    def run_manager(self, *args, ok=True):
        return self.run_script('agent-box-manage.sh', *args, ok=ok)

    def test_help_and_first_prompt_eof(self):
        for name in ('setup-agent-box.sh', 'agent-box-manage.sh'):
            self.assertIn('Usage:', self.run_script(name, '--help').stdout)
        r = self.run_script('setup-agent-box.sh', input='unknown\n', ok=False)
        self.assertTrue(r.stderr.startswith('Agent runtime: Hermes or OpenClaw?'))
        self.assertIn('Choose Hermes or OpenClaw', r.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.project / '.env').exists())

    def test_hermes_required_and_secret_round_trip(self):
        r = self.setup(bot='\ntest-bot', allow='\nbad-id\n12345')
        self.assertIn('Value is required', r.stderr)
        self.assertIn('Use numeric IDs', r.stderr)
        script = 'source "$1"; printf "%s\\n" "$HETZNER_API_TOKEN" "$MODEL_API_KEY" "$TELEGRAM_BOT_TOKEN" "$TELEGRAM_ALLOWED_USERS" "$HERMES_SSH_KEY_PASSPHRASE" "$OPENCLAW_SSH_KEY_PASSPHRASE"'
        env = subprocess.check_output(shell_command('-c', script, 'bash', str(self.project / '.env')), text=True)
        self.assertEqual(env.splitlines(), ['test-token', 'test-model-key-1234567890', 'test-bot', '12345', 'pass$`word', 'pass$`word'])
        self.assertNotIn('test-token', r.stdout + r.stderr)
        for name in ('.env', 'credentials.txt'):
            self.assertEqual((self.project / name).stat().st_mode & 0o777, 0o600)
        example = (self.project / '.env.example').read_text()
        self.assertNotIn('test-', example)
        self.assertNotIn('pass$`word', example)
        self.assertIn('HERMES_SSH_KEY_PASSPHRASE', example)
        self.assertIn('Type CREATE', r.stdout)
        self.assertNotIn("printf 'CREATE", (self.project / 'credentials.txt').read_text())
        self.assertFalse((self.project / 'boxes.json').exists())
        self.assertEqual((self.project / 'hermes-vps.sh').read_bytes(), (ROOT / 'hermes-vps.sh').read_bytes())

    def test_openclaw_optional_telegram(self):
        self.setup('OpenClaw', bot='', allow='')
        env = (self.project / '.env').read_text()
        self.assertNotIn('HERMES_', env)
        self.assertNotIn('TELEGRAM_ALLOWED_USERS', env)
        self.assertIn("TELEGRAM_BOT_TOKEN=''", env)
        self.assertIn("TELEGRAM_ALLOW_FROM=''", env)
        self.assertIn('OPENCLAW_SSH_KEY_PASSPHRASE', env)
        self.assertTrue((self.project / 'openclaw-hetzner.sh').exists())
        self.assertIn('./openclaw-hetzner.sh install', (self.project / 'credentials.txt').read_text())

    def test_setup_collects_provider_fields(self):
        self.setup('OpenClaw', bot='', allow='')
        env = (self.project / '.env').read_text()
        for value in ('MODEL_PROVIDER=testai', 'MODEL_BASE_URL=https://api.testai.example/v1',
                      'MODEL_API_KEY=test-model-key-1234567890', 'MODEL_ID=testai/model-1'):
            self.assertIn(value, env)

    def test_setup_rejects_short_provider_key(self):
        result = self.run_script('setup-agent-box.sh', input='OpenClaw\ndorian\nDorian\nn\n\n\ntest-token\ntestai\nhttps://api.testai.example/v1\nshort\ntest-model-key-1234567890\ntestai/model-1\n\n\n\n\npass\n')
        self.assertIn('looks truncated', result.stderr)

    def test_legacy_key_reuse_and_type_override(self):
        legacy = self.home / '.ssh/openclaw_hetzner_passphrase_ed25519'
        self.key.rename(legacy)
        Path(str(self.key) + '.pub').rename(Path(str(legacy) + '.pub'))
        self.env.update(HETZNER_SERVER_TYPE='cax11', HETZNER_LOCATION='hel1')
        self.setup('OpenClaw', bot='', allow='')
        env = (self.project / '.env').read_text()
        self.assertIn(str(legacy) + '.pub', env)
        self.assertIn('HETZNER_SERVER_TYPE=cax11', env)
        self.assertIn('HETZNER_LOCATION=hel1', env)
        self.assertEqual(self.calls.read_text(), 'curl\n')

    def test_server_type_location_validation(self):
        self.setup('OpenClaw', bot='', allow='', server_type='cx23', location='fsn1')
        self.assertTrue((self.project / '.env').exists())

    def test_cax11_default_location_fails_before_later_secrets_and_writes(self):
        result = self.setup('OpenClaw', bot='', allow='', server_type='cax11', ok=False)
        self.assertNotIn('Z.AI API key', result.stderr)
        for name in ('.env', '.env.example', 'credentials.txt', '.gitignore'):
            self.assertFalse((self.project / name).exists(), name)

    def test_unavailable_location_prints_available_alternatives(self):
        import json as _json
        payload = _json.dumps({'server_types': [
            {'name': 'cx23', 'locations': ['nbg1', 'hel1']},
            {'name': 'cax11', 'locations': ['nbg1', 'hel1']},
        ]})
        self.stub(self.bin / 'curl', 'cat <<\'JSON\'\n' + payload + '\nJSON\n')
        result = self.setup('OpenClaw', bot='', allow='', server_type='cx23', location='fsn1', ok=False)
        self.assertIn('available: nbg1, hel1', result.stderr)
        self.assertIn('consider: nbg1', result.stderr)

    def test_unknown_server_type_fails(self):
        result = self.setup('OpenClaw', bot='', allow='', server_type='cx99', location='fsn1', ok=False)
        self.assertIn('Unknown', result.stderr)

    def test_cax11_nbg1_passes(self):
        self.setup('OpenClaw', bot='', allow='', server_type='cax11', location='nbg1')
        self.assertIn('HETZNER_SERVER_TYPE=cax11', (self.project / '.env').read_text())

    def test_token_is_passed_via_header_file(self):
        self.setup()
        self.assertNotIn('TOKEN_ON_ARG', self.calls.read_text())
        self.assertEqual((self.calls.with_name(self.calls.name + '.header')).read_text(),
                         'Authorization: Bearer test-token\n')

    def test_in_project_private_key_is_rejected(self):
        result = self.setup(key_path='inside-key', ok=False)
        self.assertIn('outside the project', result.stderr)
        self.assertFalse((self.project / 'inside-key').exists())

    def test_setup_refuses_tracked_output_target(self):
        tracked = self.project / 'tracked.env'
        tracked.write_text('tracked')
        self.stub_tracked_git('tracked.env')
        result = self.run_script('setup-agent-box.sh', '--env-file', 'tracked.env',
                                 input='Hermes\n', ok=False)
        self.assertIn('already tracked', result.stderr)
        self.assertEqual(tracked.read_text(), 'tracked')

    def test_manage_refuses_tracked_state_target(self):
        tracked = self.project / 'tracked-state.json'
        tracked.write_text('{"version":1,"boxes":[]}\n')
        self.stub_tracked_git('tracked-state.json')
        result = self.run_script(
            'agent-box-manage.sh', 'register', '--state', 'tracked-state.json',
            '--runtime', 'hermes', '--box', 'test-box', '--server-id', '123',
            '--server-type', 'cx23', '--location', 'fsn1', '--public-ip', '192.0.2.1',
            '--tailscale-ip', '100.64.0.10', '--ssh-key', str(self.key), ok=False)
        self.assertIn('already tracked', result.stderr)

    def test_invalid_token_and_empty_token_cancel(self):
        self.run_script('setup-agent-box.sh', input='Hermes\n\n\n\n', ok=False)
        self.assertFalse(self.calls.exists())
        self.env['CURL_EXIT'] = '22'
        r = self.run_script('setup-agent-box.sh', input='OpenClaw\ndorian\nDorian\nn\n\n\ntest-invalid\n', ok=False)
        self.assertIn('validation failed', r.stderr)
        self.assertFalse((self.project / '.env').exists())

    def test_preserve_existing_secrets(self):
        self.setup()
        before = (self.project / '.env').read_bytes()
        self.run_script('setup-agent-box.sh', input='OpenClaw\ndorian\nDorian\nn\n\n\ntest-token\nn\ny\n')
        self.assertEqual(before, (self.project / '.env').read_bytes())
        self.assertNotIn('HERMES_', (self.project / '.env.example').read_text())


    def run_hetzner_functions(self, body, with_local_vps=False, extra_env=None, runtime='openclaw'):
        """Run wrapper functions with $0 pointing at a copy next to an optional local vps script."""
        source = (ROOT / f'{runtime}-hetzner.sh').read_text().rsplit('\nmain "$@"', 1)[0]
        script_dir = self.base / 'hetzner-dir'
        script_dir.mkdir(exist_ok=True)
        copy = script_dir / f'{runtime}-hetzner.sh'
        copy.write_text(source)
        if with_local_vps:
            (script_dir / f'{runtime}-vps.sh').write_text('#!/usr/bin/env bash\ntrue\n')
        env = dict(
            self.env,
            CREATED_SERVER_IP='192.0.2.1',
            SSH_PRIVATE_KEY_PATH=str(self.key),
            MODEL_PROVIDER='testai', MODEL_BASE_URL='https://api.testai.example/v1',
            MODEL_API_KEY='test-model-key', MODEL_ID='testai/model-1',
        )
        if runtime == 'openclaw':
            env['OPENCLAW_TIMEZONE'] = 'UTC'
        else:
            env.update(HERMES_TIMEZONE='UTC', HERMES_TERMINAL_BACKEND='local', HERMES_SUDO_NOPASSWD='0')
        if extra_env:
            env.update(extra_env)
        overrides = '\nCREATED_SERVER_IP="192.0.2.1"\nSSH_PRIVATE_KEY_PATH=%s\nKEEP_PUBLIC_SSH="${KEEP_FLAG:-0}"\n' % repr(str(self.key))
        if runtime == 'hermes':
            command = 'source "$1"' + overrides + body
        else:
            command = source + overrides + body
        return subprocess.run(
            shell_command('-c', command, str(copy), str(copy)),
            cwd=self.project, env=env, text=True, capture_output=True, timeout=15,
        )

    def stub_scp_and_capture_ssh(self):
        self.stub(self.bin / 'ssh', 'printf \'%s\\n\' "$@" >> "$CALLS"\ncat > "$CALLS.stdin"\n')
        self.stub(self.bin / 'scp', 'printf "scp %s\\n" "$@" >> "$CALLS"\n')

    def test_write_remote_env_file_forwards_tailscale_auth_key_when_set(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions(
            'write_remote_env_file', extra_env={
                'TAILSCALE_AUTH_KEY': 'tsauth key',
                'MODEL_CATALOG': 'testai/model-1,testai/model-2',
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stdin = self.calls.with_name(self.calls.name + '.stdin').read_text()
        self.assertIn('TAILSCALE_AUTH_KEY=tsauth\\ key', stdin)
        self.assertIn('MODEL_CATALOG=testai/model-1\\,testai/model-2', stdin)
        self.assertIn('MODEL_API_KEY=test-model-key', stdin)

    def test_write_remote_env_file_omits_tailscale_auth_key_when_unset(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions('write_remote_env_file')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stdin = self.calls.with_name(self.calls.name + '.stdin').read_text()
        self.assertNotIn('TAILSCALE_AUTH_KEY', stdin)
        self.assertNotIn('MODEL_CATALOG', stdin)
        self.assertIn('MODEL_API_KEY=test-model-key', stdin)

    def test_hermes_write_remote_env_file_forwards_tailscale_auth_key_when_set(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions(
            'write_remote_env_file', extra_env={'TAILSCALE_AUTH_KEY': 'tsauth key'}, runtime='hermes'
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stdin = self.calls.with_name(self.calls.name + '.stdin').read_text()
        self.assertIn('TAILSCALE_AUTH_KEY=tsauth\\ key', stdin)
        self.assertIn('MODEL_API_KEY=test-model-key', stdin)

    def test_hermes_write_remote_env_file_omits_tailscale_auth_key_when_unset(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions('write_remote_env_file', runtime='hermes')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stdin = self.calls.with_name(self.calls.name + '.stdin').read_text()
        self.assertNotIn('TAILSCALE_AUTH_KEY', stdin)
        self.assertIn('MODEL_API_KEY=test-model-key', stdin)

    def test_run_remote_installer_prefers_local_vps_script_via_scp(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions(
            'run_remote_installer',
            with_local_vps=True,
            extra_env={'TAILSCALE_AUTH_KEY': 'tsauth', 'KEEP_FLAG': '1'},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertTrue(any(line.startswith('scp ') for line in calls), calls)
        self.assertTrue(any(line.endswith('root@192.0.2.1:/root/openclaw-vps.sh') for line in calls), calls)
        remote_command = calls[-1]
        self.assertIn('chmod +x /root/openclaw-vps.sh', remote_command)
        self.assertIn('/root/openclaw-vps.sh install --keep-public-ssh', remote_command)
        self.assertNotIn('curl', remote_command)
        self.assertIn('using local openclaw-vps.sh from repo', result.stdout)

    def test_run_remote_installer_feeds_prompt_lines_to_ssh(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions('run_remote_installer')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.calls.with_name(self.calls.name + '.stdin').read_text(),
            '\n\n\n\n',
        )

    def test_run_remote_installer_falls_back_to_curl_without_local_script(self):
        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions('run_remote_installer')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertFalse(any(line.startswith('scp ') for line in calls), calls)
        remote_command = calls[-1]
        self.assertIn('curl -fsSL', remote_command)
        self.assertIn('/root/openclaw-vps.sh install ', remote_command)
        self.assertIn('downloading and running remote OpenClaw VPS installer', result.stdout)

    def test_wrong_passphrase_fails_fast_without_askpass_retry(self):
        self.stub_scp_and_capture_ssh()
        self.stub(self.bin / 'ssh-add', 'printf "ssh-add\\n" >> "$CALLS"\nexit 1\n')
        self.stub(self.bin / 'ssh-keygen', 'if [[ "$1" == "-y" ]]; then exit 255; fi\nexit 0\n')
        result = self.run_hetzner_functions(
            'load_selected_ssh_key',
            extra_env={'OPENCLAW_SSH_KEY_PASSPHRASE': 'wrong-pass',
                       'SSH_AUTH_SOCK': str(self.base / 'fake-sock')},
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('passphrase is incorrect', result.stderr)
        calls = self.calls.read_text().splitlines()
        ssh_add_count = sum(1 for line in calls if line == 'ssh-add')
        self.assertLessEqual(ssh_add_count, 1, calls)

    def test_credentials_file_persisted_600_and_tracked_refused(self):
        for runtime in ('openclaw', 'hermes'):
            source = (ROOT / f'{runtime}-hetzner.sh').read_text().rsplit('\nmain "$@"', 1)[0]
            partial = self.base / f'{runtime}-hetzner-partial.sh'
            partial.write_text(source)
            env = dict(self.env, ROOT_PASSWORD=f'{runtime}-root-password')
            result = subprocess.run(
                shell_command('-c', 'source "$1"\nROOT_PASSWORD=$2\nparse_args --credentials-file saved.txt\nprint_summary', 'bash', str(partial), f'{runtime}-root-password'),
                cwd=self.project, env=env, text=True, capture_output=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            saved = self.project / 'saved.txt'
            self.assertEqual(saved.read_text(), f'ROOT_PASSWORD={runtime}-root-password\n')
            self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
            self.assertIn('saved root password to saved.txt', result.stdout)
            saved.unlink()

            tracked = self.project / 'tracked-credentials.txt'
            tracked.write_text('keep me\n')
            self.stub_tracked_git(tracked.name)
            result = subprocess.run(
                shell_command('-c', 'source "$1"\nROOT_PASSWORD=$2\nparse_args --credentials-file tracked-credentials.txt\nprint_summary', 'bash', str(partial), f'{runtime}-root-password'),
                cwd=self.project, env=env, text=True, capture_output=True, timeout=15,
            )
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('refusing tracked credentials file', result.stderr)
            self.assertEqual(tracked.read_text(), 'keep me\n')
            tracked.unlink()

    def test_install_seeds_provider_auth_via_paste_token(self):
        self.stub(self.bin / 'sudo', r'''
while (($#)); do
    if [[ "$1" == "bash" ]]; then
        shift
        exec bash "$@"
    fi
    shift
done
exit 1
''')
        self.stub(self.bin / 'openclaw', r'''
printf 'args=%s\n' "$*" >> "$CALLS"
printf 'stdin=%s\n' "$(cat)" >> "$CALLS"
''')
        state = self.base / 'auth-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR" "$USER_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[
  {"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}},
  {"id":"reviewer","group":"main","workspace":"/tmp/reviewer","agentDir":"/tmp/reviewer-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}
]}\n' > "$AGENTS_FILE"
printf 'MODEL_PROVIDER=%q\nMODEL_BASE_URL=%q\nMODEL_API_KEY=%q\nMODEL_ID=%q\n' 'testai' 'https://api.testai.example/v1' 'test-model-key' 'testai/model-1' > "$USER_ENV_FILE"
install() {
    local -a paths=()
    while (($#)); do
        case "$1" in
            -o|-g|-m) shift 2 ;;
            -d) shift ;;
            *) paths+=("$1"); shift ;;
        esac
    done
    mkdir -p "${paths[@]}"
}
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
printf '{"models":{"providers":{"wrong-provider":{}}}}\n' > "$OPENCLAW_CONFIG_FILE"
seed_provider_auth
''', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text().splitlines()
        args = [line.removeprefix('args=') for line in calls if line.startswith('args=')]
        stdin = [line.removeprefix('stdin=') for line in calls if line.startswith('stdin=')]
        self.assertEqual(args, [
            'models auth paste-token --provider testai --agent main',
            'models auth paste-token --provider testai --agent reviewer',
        ])
        self.assertEqual(stdin, ['test-model-key', 'test-model-key'])
        self.assertNotIn('models auth login', self.calls.read_text())

    def test_no_modelpolicy_in_generated_config(self):
        state = self.base / 'config-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() {
    local -a paths=()
    while (($#)); do
        case "$1" in
            -o|-g|-m) shift 2 ;;
            -d) shift ;;
            *) paths+=("$1"); shift ;;
        esac
    done
    mkdir -p "${paths[@]}"
}
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
OPENCODE_CONFIG_DIR="$STATE_DIR/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
regenerate_openclaw_config
''', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = json.loads((state / 'config' / 'openclaw.json').read_text())
        self.assertNotIn('models', config['agents']['defaults'])
        self.assertNotIn('modelPolicy', json.dumps(config))

    def test_catalog_lists_all_models(self):
        state = self.base / 'catalog-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_CATALOG': 'testai/model-1,testai/model-2,testai/model-3'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        models = json.loads((state / 'config' / 'openclaw.json').read_text())['models']['providers']['testai']['models']
        self.assertEqual({model['id'] for model in models}, {'model-1', 'model-2', 'model-3'})
        self.assertEqual({model['name'] for model in models}, {'testai/model-1', 'testai/model-2', 'testai/model-3'})

    def test_catalog_defaults_to_primary_only(self):
        state = self.base / 'catalog-default-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_CATALOG': ''})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        models = json.loads((state / 'config' / 'openclaw.json').read_text())['models']['providers']['testai']['models']
        self.assertEqual(models, [{'id': 'model-1', 'name': 'testai/model-1'}])

    def test_catalog_auto_discovers_from_provider_endpoint(self):
        state = self.base / 'catalog-discovery-state'
        models_file = self.base / 'models.json'
        models_file.write_text('{"object":"list","data":[{"id":"model-a"},{"id":"model-b"},{"id":"model-c"}]}')
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_CATALOG': '', 'MODELS_JSON_FILE': str(models_file)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        models = json.loads((state / 'config' / 'openclaw.json').read_text())['models']['providers']['testai']['models']
        self.assertEqual({model['id'] for model in models}, {'model-a', 'model-b', 'model-c', 'model-1'})
        self.assertEqual({model['name'] for model in models}, {'testai/model-a', 'testai/model-b', 'testai/model-c', 'testai/model-1'})

    def test_manual_catalog_overrides_discovery(self):
        state = self.base / 'catalog-manual-state'
        models_file = self.base / 'models-manual.json'
        models_file.write_text('{"object":"list","data":[{"id":"model-a"},{"id":"model-b"}]}')
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_CATALOG': 'testai/manual-1', 'MODELS_JSON_FILE': str(models_file)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        models = json.loads((state / 'config' / 'openclaw.json').read_text())['models']['providers']['testai']['models']
        self.assertEqual(models, [{'id': 'manual-1', 'name': 'testai/manual-1'}, {'id': 'model-1', 'name': 'testai/model-1'}])

    def test_config_uses_configured_provider(self):
        state = self.base / 'provider-config-state'
        result = self.run_vps_functions(r'''
OPENCODE_CONFIG_DIR="$STATE_DIR/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
write_opencode_config
''', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        openclaw = (state / 'config' / 'openclaw.json').read_text()
        config = json.loads(openclaw)
        opencode = (state / 'opencode' / 'opencode.json').read_text()
        self.assertIn('"testai"', openclaw)
        self.assertIn('https://api.testai.example/v1', openclaw)
        self.assertIn('"testai"', opencode)
        self.assertIn('https://api.testai.example/v1', opencode)
        self.assertIn('testai/model-1', openclaw)
        self.assertIn('testai/model-1', opencode)
        self.assertNotIn('zai', openclaw.lower())
        self.assertNotIn('zai', opencode.lower())
        self.assertIn('"mode": "merge"', openclaw)
        self.assertNotIn('modelPolicy', openclaw)
        self.assertEqual(config['gateway']['trustedProxies'], ['127.0.0.1', '::1'])
        agents = config['agents']['list']
        self.assertEqual([(agent['id'], agent['name'], agent['identity']['name'], agent['default']) for agent in agents],
                         [('main', 'main', 'main', True)])

    def test_agent_labels_and_default(self):
        state = self.base / 'agent-labels-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[
  {"id":"dorian","label":"Dorian","workspace":"/tmp/dorian","agentDir":"/tmp/dorian-agent","group":"main","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}},
  {"id":"boros","label":"Boros","workspace":"/tmp/boros","agentDir":"/tmp/boros-agent","group":"main","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}
]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        agents = json.loads((state / 'config' / 'openclaw.json').read_text())['agents']['list']
        self.assertEqual([(agent['id'], agent['name'], agent['identity']['name']) for agent in agents],
                         [('dorian', 'dorian', 'Dorian'), ('boros', 'boros', 'Boros')])
        self.assertEqual([agent['id'] for agent in agents if agent['default']], ['dorian'])

    def test_per_agent_state_fields_projected(self):
        state = self.base / 'per-agent-state-fields-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}' > "$GROUPS_FILE"
printf '%s\n' '{"agents":[' \
  '{"id":"reze","group":"main","workspace":"/tmp/reze","agentDir":"/tmp/reze-agent","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"},"subagents":{"model":"testai/subagent","thinking":"high","delegationMode":"parallel"},"skills":["github","summarize"],"contextInjection":"continuation-skip","bootstrapMaxChars":8000,"bootstrapTotalMaxChars":8000,"tools":{"alsoAllow":["browser","web_fetch"],"sandbox":{"mode":"all"}},"heartbeat":{"every":"0m"}},' \
  '{"id":"dorian","group":"main","workspace":"/tmp/dorian","agentDir":"/tmp/dorian-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}' \
  ']}' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        agents = {agent['id']: agent for agent in json.loads(
            (state / 'config' / 'openclaw.json').read_text())['agents']['list']}
        self.assertEqual(agents['reze']['subagents'], {
            'model': 'testai/subagent', 'thinking': 'high', 'delegationMode': 'parallel'})
        self.assertEqual(agents['reze']['skills'], ['github', 'summarize'])
        self.assertEqual(agents['reze']['contextInjection'], 'continuation-skip')
        self.assertEqual(agents['reze']['bootstrapMaxChars'], 8000)
        self.assertEqual(agents['reze']['bootstrapTotalMaxChars'], 8000)
        self.assertEqual(agents['reze']['tools'], {
            'alsoAllow': ['browser', 'web_fetch'], 'sandbox': {'mode': 'all'}})
        self.assertEqual(agents['reze']['heartbeat'], {'every': '0m'})
        for field in ('subagents', 'skills', 'contextInjection', 'bootstrapMaxChars',
                      'bootstrapTotalMaxChars', 'tools', 'heartbeat'):
            self.assertNotIn(field, agents['dorian'])

    def test_agent_skills_precedence(self):
        def refresh(agent_records, skills_csv):
            state = self.base / ('skills-precedence-' + str(refresh.counter))
            refresh.counter += 1
            result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}' > "$GROUPS_FILE"
printf '%s\n' "$AGENTS_JSON" > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={
                'AGENTS_JSON': json.dumps({'agents': agent_records}),
                'OPENCLAW_AGENT_SKILLS': skills_csv,
            })
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return {agent['id']: agent for agent in json.loads(
                (state / 'config' / 'openclaw.json').read_text())['agents']['list']}

        refresh.counter = 0
        common = lambda agent: {
            'id': agent, 'group': 'main', 'workspace': '/tmp/' + agent,
            'agentDir': '/tmp/' + agent + '-agent', 'telegramTokenEnv': '',
            'telegramAllowFrom': '', 'ownerAllowFrom': '', 'sandbox': {'mode': 'off'}}
        reze = common('reze')
        reze['skills'] = ['a']
        agents = refresh([reze, common('dorian')], 'x,y')
        self.assertEqual(agents['reze']['skills'], ['a'])
        self.assertEqual(agents['dorian']['skills'], ['x', 'y'])

        reze = common('reze')
        reze['skills'] = []
        self.assertEqual(refresh([reze], 'x,y')['reze']['skills'], [])

        self.assertEqual(refresh([common('reze')], 'x,y')['reze']['skills'], ['x', 'y'])

        agents = refresh([common('reze')], '')
        self.assertNotIn('skills', agents['reze'])

    def test_malformed_agent_state_fails_refresh(self):
        state = self.base / 'malformed-agent-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}' > "$GROUPS_FILE"
printf '%s\n' '{"agents":[{"id":"reze","group":"main","workspace":"/tmp/reze","agentDir":"/tmp/reze-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"},"subagents":"wrong"}]}' > "$AGENTS_FILE"
printf '%s\n' '{"sentinel":true}' > "$OPENCLAW_CONFIG_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid agents.json: agent "reze" field "subagents" must be object', result.stderr)
        self.assertEqual((state / 'config' / 'openclaw.json').read_text(), '{"sentinel":true}\n')

    def test_refresh_preserves_operator_sections(self):
        state = self.base / 'preserve-operator-sections-state'
        preserved = {
            'plugins': {'entries': {'duckduckgo': {'enabled': True, 'config': {'region': 'us'}}},
                        'installs': {'junk': True}},
            'mcp': {'servers': {'x': {}}},
            'secrets': {'providers': {'default': {}}},
            'tools': {'web': {'search': {'provider': 'duckduckgo'}}},
        }
        result = self._run_refresh_with_config(state, preserved)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = json.loads((state / 'config' / 'openclaw.json').read_text())
        self.assertEqual(config['plugins'], {'entries': preserved['plugins']['entries']})
        self.assertEqual(config['mcp'], preserved['mcp'])
        self.assertEqual(config['secrets'], preserved['secrets'])
        self.assertEqual(config['tools']['web'], preserved['tools']['web'])
        self.assertNotIn('installs', config['plugins'])

    def test_refresh_replaces_managed_sections(self):
        state = self.base / 'replace-managed-sections-state'
        hostile = {
            'agents': {'entries': {'evil': {}}},
            'models': {'providers': {'evil': {}}},
            'gateway': {'bind': '0.0.0.0'},
            'tools': {'profile': 'full', 'exec': {'host': 'remote'},
                      'web': {'search': {'provider': 'duckduckgo'}}},
        }
        result = self._run_refresh_with_config(state, hostile)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = json.loads((state / 'config' / 'openclaw.json').read_text())
        self.assertEqual([agent['id'] for agent in config['agents']['list']], ['main'])
        self.assertNotIn('evil', config['models']['providers'])
        self.assertEqual(config['models']['mode'], 'merge')
        self.assertEqual(config['gateway']['bind'], 'loopback')
        self.assertEqual(config['tools']['profile'], 'coding')
        self.assertEqual(config['tools']['exec'], {
            'host': 'gateway', 'security': 'allowlist', 'ask': 'off', 'strictInlineEval': True})
        self.assertEqual(config['tools']['web'], hostile['tools']['web'])

    def test_refresh_invalid_current_config_uses_empty_snapshot(self):
        state = self.base / 'invalid-current-config-state'
        result = self._run_refresh_with_config(state, None, config_text='not json\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('current OpenClaw config is missing or invalid', result.stdout + result.stderr)
        json.loads((state / 'config' / 'openclaw.json').read_text())

    def test_refresh_idempotent(self):
        state = self.base / 'idempotent-refresh-state'
        preserved = {
            'plugins': {'entries': {'duckduckgo': {'enabled': True}}},
            'mcp': {'servers': {'x': {}}},
            'secrets': {'providers': {'default': {}}},
            'tools': {'web': {'search': {'provider': 'duckduckgo'}}},
        }
        first = self._run_refresh_with_config(state, preserved)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        first_text = (state / 'config' / 'openclaw.json').read_text()
        second = self._run_refresh_with_config(state, None)
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        second_text = (state / 'config' / 'openclaw.json').read_text()
        self.assertEqual(second_text, first_text)
        config = json.loads(second_text)
        self.assertEqual(config['plugins'], preserved['plugins'])
        self.assertEqual(config['mcp'], preserved['mcp'])
        self.assertEqual(config['secrets'], preserved['secrets'])
        self.assertEqual(config['tools']['web'], preserved['tools']['web'])

    def _run_refresh_with_config(self, state, config, config_text=None):
        config_setup = ''
        if config is not None or config_text is not None:
            config_value = json.dumps(config) if config is not None else config_text
            config_setup = "printf '%%s\\n' %r > \"$OPENCLAW_CONFIG_FILE\"" % (config_value,)
        return self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}' > "$GROUPS_FILE"
printf '%s\n' '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}' > "$AGENTS_FILE"
''' + config_setup + r'''
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state)

    def test_refresh_config_loads_model_env_from_file(self):
        state = self.base / 'refresh-model-env-state'
        result = self.run_vps_functions(r'''
MODEL_PROVIDER=''
MODEL_BASE_URL=''
MODEL_API_KEY=''
MODEL_ID=''
USER_ENV_FILE="$STATE_DIR/model-env"
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '%s\n' "MODEL_PROVIDER=testai" "MODEL_BASE_URL=https://api.testai.example/v1" "MODEL_API_KEY=test-model-key" "MODEL_ID=testai/model-1" > "$USER_ENV_FILE"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_PROVIDER': '', 'MODEL_BASE_URL': '', 'MODEL_API_KEY': '', 'MODEL_ID': ''})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = json.loads((state / 'config' / 'openclaw.json').read_text())
        self.assertIn('testai', config['models']['providers'])
        self.assertEqual(config['models']['providers']['testai']['baseUrl'], 'https://api.testai.example/v1')
        self.assertEqual(config['models']['mode'], 'merge')

    def test_legacy_zai_env_still_seeds_and_configures(self):
        state = self.base / 'legacy-model-env-state'
        result = self.run_vps_functions(r'''
MODEL_PROVIDER=''
MODEL_BASE_URL=''
MODEL_API_KEY=''
MODEL_ID=''
USER_ENV_FILE="$STATE_DIR/model-env"
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '%s\n' 'ZAI_API_KEY=legacy-key-1234567890' > "$USER_ENV_FILE"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","sandbox":{"mode":"off"}}]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
ensure_state_files() { :; }
sync_all_agent_workspace_skills() { :; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
load_model_env_from_file
regenerate_openclaw_config
''', state=state, extra_env={'MODEL_PROVIDER': '', 'MODEL_BASE_URL': '', 'MODEL_API_KEY': '', 'MODEL_ID': ''})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        config = json.loads((state / 'config' / 'openclaw.json').read_text())
        provider = config['models']['providers']['zai']
        self.assertEqual(provider['baseUrl'], 'https://api.z.ai/api/coding/paas/v4')
        self.assertEqual(provider['models'][0]['name'], 'zai/glm-5.3')
        self.assertIn('legacy ZAI_API_KEY found in env file; using it as MODEL_API_KEY', result.stdout)

    def run_install_with_approval_import(self, exit_code, add_exit=0, tools_exit=0):
        self.stub_envfix_openclaw()
        state = self.base / 'approval-state'
        return self.run_vps_functions(r'''
ensure_git_gh_installed() { printf 'tools\n' >> "$CALLS"; return "${TOOLS_EXIT:-0}"; }
resolve_verified_host_tool() { printf '/usr/bin/%s\n' "$1"; }
preflight() { :; }
apt_install_hardening_first() { :; }
configure_ssh_hardening() { :; }
configure_fail2ban() { :; }
configure_unattended_upgrades() { :; }
configure_host_timezone() { :; }
prompt_secret() {
    if [[ "$1" == "MODEL_API_KEY" ]]; then
        printf 'test-model-key'
    fi
    return 0
}
ensure_app_user() { :; }
install_tailscale() { :; }
tailscale_up() { :; }
install_node() { :; }
install_incus() { :; }
install_openclaw_and_opencode() { :; }
write_user_env() { :; }
ensure_user_shell_sources_env() { :; }
ensure_group() { :; }
agent_exists() { return 0; }
ensure_agent() { :; }
regenerate_openclaw_config() { :; }
seed_provider_auth() { :; }
write_opencode_config() { :; }
install_user_systemd_service() { printf 'service\n' >> "$CALLS"; }
write_helper_scripts() { :; }
write_systemd_timers() { :; }
install() {
    local path
    while (($#)); do
        case "$1" in
            -o|-g|-m) shift 2 ;;
            -d) shift ;;
            *) path="$1"; mkdir -p "$path"; shift ;;
        esac
    done
}
chown() { :; }
chmod() { /bin/chmod "$@"; }
install_all
''', state=state, extra_env={'OPENCLAW_APPROVALS_EXIT': str(exit_code), 'ADD_EXIT': str(add_exit), 'TOOLS_EXIT': str(tools_exit),
                             'OPENCLAW_INITIAL_AGENT_ID': 'dorian',
                             'OPENCLAW_INITIAL_AGENT_LABEL': 'Dorian'})

    def test_envfix_approvals_imports_before_service_without_legacy_file(self):
        result = self.run_install_with_approval_import(0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.base / 'approval-state'
        calls = self.calls.read_text().splitlines()
        self.assertIn(f'openclaw approvals set --file {state}/exec-approvals.pending.json', calls)
        self.assertLess(calls.index(f'openclaw approvals set --file {state}/exec-approvals.pending.json'), calls.index('service'))
        for tool in ('git', 'gh'):
            self.assertLess(calls.index(f'openclaw approvals allowlist add --agent * /usr/bin/{tool}'), calls.index('service'))
        self.assertFalse((state / 'exec-approvals.pending.json').exists())
        self.assertFalse((state / 'config' / 'exec-approvals.json').exists())

    def test_envfix_approvals_import_failure_prevents_service_without_legacy_file(self):
        result = self.run_install_with_approval_import(1)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.base / 'approval-state'
        self.assertIn('approvals import failed', result.stderr)
        self.assertFalse((state / 'config/exec-approvals.json').exists())
        pending = state / 'exec-approvals.pending.json'
        self.assertTrue(pending.exists())
        self.assertEqual(pending.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('service', self.calls.read_text().splitlines())
        self.assertNotIn('install complete', result.stdout)

    def test_preflight_catches_short_provider_key_and_bad_location(self):
        self.env.update(
            OPENCLAW_INITIAL_AGENT_ID='dorian',
            HETZNER_API_TOKEN='test-token-1234567890ab',
            HETZNER_SERVER_TYPE='cx23',
            HETZNER_LOCATION='xx99',
            SSH_PUBLIC_KEY_PATH=str(self.key) + '.pub',
            MODEL_API_KEY='123456',
        )
        r = self.run_script('openclaw-hetzner.sh', 'preflight', ok=False)
        self.assertIn('not available for cx23', r.stderr)
        self.assertIn('xx99', r.stderr)
        self.assertIn('truncated', r.stderr)

    def test_preflight_passes_clean_env(self):
        self.env.update(
            OPENCLAW_INITIAL_AGENT_ID='dorian',
            HETZNER_API_TOKEN='test-token-1234567890ab',
            HETZNER_SERVER_TYPE='cx23',
            HETZNER_LOCATION='fsn1',
            SSH_PUBLIC_KEY_PATH=str(self.key) + '.pub',
            MODEL_PROVIDER='testai', MODEL_BASE_URL='https://api.testai.example/v1',
            MODEL_API_KEY='test-model-key-1234567890abcdef', MODEL_ID='testai/model-1',
        )
        r = self.run_script('openclaw-hetzner.sh', 'preflight')
        self.assertIn('all checks passed', r.stdout)
        rh = self.run_script('hermes-hetzner.sh', 'preflight')
        self.assertIn('all checks passed', rh.stdout)

    def test_register_dispatch_and_successful_state_update(self):
        self.register()
        self.wrapper('hermes')
        self.run_script('agent-box-manage.sh', 'status')
        self.assertEqual(self.calls.read_text().splitlines(), ['status', '--host', '100.64.0.10', '--ssh-key', str(self.key)+'.pub', '--group', 'default'])
        self.run_script('agent-box-manage.sh', 'add-group', '--group', 'Work_2')
        self.assertIn('Work_2', self.state()['boxes'][0]['groups'])
        self.assertEqual((self.project / 'boxes.json').stat().st_mode & 0o777, 0o600)
        self.run_script('agent-box-manage.sh', 'lockdown')
        self.assertEqual(self.calls.read_text().splitlines(), ['-tt', '-o', 'IdentitiesOnly=yes', '-i', str(self.key), 'root@100.64.0.10', '/root/hermes-vps.sh lockdown'])

    def test_openclaw_dispatch_and_failed_mutation(self):
        self.register('openclaw')
        self.wrapper('openclaw')
        for command in ('status', 'doctor', 'logs', 'backup', 'maintenance', 'refresh-config', 'list', 'lockdown'):
            self.run_script('agent-box-manage.sh', command)
            self.assertIn(f'/root/openclaw-vps.sh {command}', self.calls.read_text())
            self.assertIn('-tt\n', self.calls.read_text())
        self.run_script('agent-box-manage.sh', 'add-agent', '--agent', 'reviewer', '--group', 'coding')
        self.assertIn({'id':'reviewer','group':'coding'}, self.state()['boxes'][0]['agents'])
        before = (self.project / 'boxes.json').read_bytes()
        self.env['REMOTE_EXIT'] = '9'
        self.run_script('agent-box-manage.sh', 'add-group', '--group', 'failed', ok=False)
        self.assertEqual(before, (self.project / 'boxes.json').read_bytes())
        self.assertFalse((self.project / 'boxes.json.lock').exists())

    def test_invalid_state_and_argument_injection(self):
        self.register('openclaw')
        for args in [('status', '--group', 'main'), ('add-group', '--group', 'bad;touch /tmp/nope'), ('add-agent', '--agent', 'bad_id', '--group', 'main'), ('status', '--yes', '1')]:
            self.run_script('agent-box-manage.sh', *args, ok=False)
        self.assertFalse(self.calls.exists())
        state = self.state()
        state['boxes'][0]['password'] = 'not-allowed'
        (self.project / 'boxes.json').write_text(json.dumps(state))
        self.run_script('agent-box-manage.sh', 'status', ok=False)
        self.assertFalse(self.calls.exists())

    def test_multi_box_resolution_and_duplicate_preservation(self):
        self.register()
        self.register('openclaw', 'second', '456')
        before = (self.project / 'boxes.json').read_bytes()
        self.register(ok=False)
        self.assertEqual(before, (self.project / 'boxes.json').read_bytes())
        self.run_script('agent-box-manage.sh', 'status', ok=False)
        self.run_script('agent-box-manage.sh', 'status', '--box', 'missing', ok=False)
        self.run_script('agent-box-manage.sh', 'status', '--box', 'second')
        self.assertIn('/root/openclaw-vps.sh status', self.calls.read_text())
        self.assertIn('second\topenclaw', self.run_script('agent-box-manage.sh', 'boxes').stdout)

    def test_gitignore_custom_outputs_and_backups(self):
        self.setup(env_options=('--env-file', '.env.work', '--credentials-file', 'credentials work.txt'))
        self.register()
        ignored = ['.env.work', '.env.work.bak.test', 'credentials work.txt',
                   'credentials work.txt.bak.test', 'boxes.json', 'boxes.json.tmp.test', 'boxes.json.lock']
        patterns = [pat.lstrip('/').replace(r'\ ', ' ') for pat in
                    (self.project / '.gitignore').read_text().splitlines() if pat and not pat.startswith('#')]
        for name in ignored:
            self.assertTrue(any(fnmatch.fnmatchcase(name, pat) for pat in patterns), name)
        for name in ('.env.example', 'boxes.example.json'):
            self.assertFalse(any(fnmatch.fnmatchcase(name, pat) for pat in patterns), name)

    def test_real_wrappers_with_stubbed_ssh(self):
        self.register()
        self.register('openclaw', 'second', '456')
        self.env['SSH_AUTH_SOCK'] = str(self.base / 'fake-socket')
        self.stub(self.bin / 'ssh-add', 'exit 0\n')
        for runtime in ('hermes', 'openclaw'):
            shutil.copy2(ROOT / f'{runtime}-hetzner.sh', self.project)
        for command in ('status', 'doctor', 'logs', 'backup', 'maintenance', 'refresh-config'):
            self.run_script('agent-box-manage.sh', command, '--box', 'test-box', '--group', 'Work_2')
            self.assertIn(f'/root/hermes-vps.sh --group Work_2 {command}', self.calls.read_text())
        self.run_script('agent-box-manage.sh', 'add-group', '--box', 'test-box', '--group', 'work')
        self.assertIn('/root/hermes-vps.sh --group work add-group', self.calls.read_text())
        self.run_script('agent-box-manage.sh', 'add-group', '--box', 'second', '--group', 'work')
        self.assertIn('/root/openclaw-vps.sh add-group work', self.calls.read_text())
        self.run_script('agent-box-manage.sh', 'add-agent', '--box', 'second', '--agent', 'reviewer', '--group', 'work')
        self.assertIn('/root/openclaw-vps.sh add-agent reviewer --group work', self.calls.read_text())

    def test_new_key_default_and_secret_example_rejection(self):
        self.key.unlink()
        Path(str(self.key) + '.pub').unlink()
        self.setup()
        self.assertIn(str(self.key), self.calls.read_text())
        self.assertNotIn('openclaw_hetzner', self.calls.read_text())
        result = self.run_script('setup-agent-box.sh', '--env-file', 'leak.example.json', input='Hermes\n', ok=False)
        self.assertIn('Secret output cannot be an example', result.stderr)
        self.assertFalse((self.project / 'leak.example.json').exists())

    def test_state_lock_and_invalid_routing(self):
        self.register('openclaw')
        before = (self.project / 'boxes.json').read_bytes()
        lock = self.project / 'boxes.json.lock'
        lock.mkdir()
        self.run_script('agent-box-manage.sh', 'add-group', '--group', 'busy', ok=False)
        self.assertTrue(lock.exists())
        lock.rmdir()
        for field, value in [('tailscale_ip', '192.0.2.1'), ('public_ip', '999.1.1.1'),
                             ('paths', {'vps_script':'/root/evil.sh','state_dir':'/var/lib/openclaw-vps'})]:
            state = json.loads(before)
            state['boxes'][0][field] = value
            (self.project / 'boxes.json').write_text(json.dumps(state))
            self.run_script('agent-box-manage.sh', 'status', ok=False)
        self.assertFalse(self.calls.exists())

    def test_openclaw_serve_requires_gateway_and_does_not_enable_proxy_when_down(self):
        result = self.run_vps_functions('cmd_serve', gateway=False)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('serve --bg http://127.0.0.1:18789', self.calls.read_text() if self.calls.exists() else '')
        self.assertIn('./openclaw-vps.sh status', result.stderr)
        self.assertIn('openclaw-gateway.service', result.stderr)

    def test_openclaw_serve_enables_linger_serve_and_records_flag(self):
        state = self.base / 'serve-state'
        result = self.run_vps_functions('cmd_serve', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text()
        self.assertIn('loginctl enable-linger openclaw', calls)
        self.assertIn('tailscale serve --bg http://127.0.0.1:18789', calls)
        self.assertTrue((state / 'serve.enabled').exists())
        self.assertIn('https://openclaw-box.tail1234.ts.net', result.stdout)
        self.assertIn('gateway authentication still applies', result.stdout)
        self.assertIn('tailnet-only', result.stdout)

    def test_openclaw_serve_surfaces_tailscale_certificate_guidance(self):
        result = self.run_vps_functions(
            'cmd_serve', tailscale_exit=1,
            tailscale_error='Error: HTTPS certificates are not enabled; enable MagicDNS',
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HTTPS certificates are not enabled', result.stderr)
        self.assertIn('enable both MagicDNS and HTTPS Certificates in the Tailscale admin console', result.stderr)
        self.assertNotIn('https://openclaw-box.tail1234.ts.net', result.stdout)

    def test_openclaw_serve_off_clears_flag_and_resets_proxy(self):
        state = self.base / 'serve-off-state'
        state.mkdir()
        (state / 'serve.enabled').write_text('enabled\n')
        result = self.run_vps_functions('cmd_serve_off', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((state / 'serve.enabled').exists())
        self.assertIn('tailscale serve reset', self.calls.read_text())
        self.assertIn('disabled', result.stdout)

    def test_generated_maintenance_reasserts_only_when_serve_flag_exists(self):
        state = self.base / 'maintenance-state'
        result = self.run_vps_functions('write_maintenance_helper', state=state)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        helper = self.base / 'maintenance-helper'
        self.assertTrue(helper.exists())

        (state / 'serve.enabled').parent.mkdir(parents=True, exist_ok=True)
        (state / 'serve.enabled').write_text('enabled\n')
        self._stub_maintenance_commands()
        active = subprocess.run(shell_command(str(helper)), cwd=self.project, env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(active.returncode, 0, active.stdout + active.stderr)
        self.assertIn('tailscale serve --bg http://127.0.0.1:18789', self.calls.read_text())

        self.calls.unlink()
        (state / 'serve.enabled').unlink()
        inactive = subprocess.run(shell_command(str(helper)), cwd=self.project, env=self.env,
                                  text=True, capture_output=True, timeout=15)
        self.assertEqual(inactive.returncode, 0, inactive.stdout + inactive.stderr)
        self.assertNotIn('serve --bg', self.calls.read_text() if self.calls.exists() else '')

    def _stub_maintenance_commands(self):
        for name in ('apt-get', 'incus', 'npm', 'sudo', 'runuser', 'systemctl', 'jq'):
            self.stub(self.bin / name, 'exit 0\n')

    def test_manager_serve_is_openclaw_box_wide_and_dispatches(self):
        self.register('openclaw')
        for args in (('serve', '--group', 'main'), ('serve-off', '--agent', 'main')):
            result = self.run_manager(*args, ok=False)
            self.assertIn('box-wide', result.stderr)
            self.assertFalse(self.calls.exists())
        for command in ('serve', 'serve-off'):
            self.run_manager(command)
            self.assertIn(f'/root/openclaw-vps.sh {command}', self.calls.read_text())
            self.calls.unlink()

    def test_manager_rejects_serve_for_hermes(self):
        self.register('hermes')
        result = self.run_manager('serve', ok=False)
        self.assertIn('OpenClaw', result.stderr)
        self.assertFalse(self.calls.exists())

    def envfix_fixture(self, agents=None, config=None):
        state = self.base / ('envfix-' + str(len(list(self.base.glob('envfix-*')))))
        (state / 'config').mkdir(parents=True)
        if agents is None:
            agents = [self.envfix_agent(state, 'dorian', sandbox={'mode': 'off'})]
        (state / 'agents.json').write_text(json.dumps({'agents': agents}))
        (state / 'groups.json').write_text(json.dumps({'groups': [{'id': 'main', 'sshPort': 2222}]}))
        if config is not None:
            (state / 'config/openclaw.json').write_text(json.dumps(config))
        return state

    def envfix_agent(self, state, name, **fields):
        return dict(id=name, group='main', workspace=str(state / 'home' / ('workspace-' + name)),
                    agentDir=str(state / 'home/.openclaw/agents' / name / 'agent'),
                    telegramTokenEnv='', telegramAllowFrom='', ownerAllowFrom='', **fields)

    def envfix_run(self, state, body='regenerate_openclaw_config', extra_env=None):
        # All effects stay inside this fixture; unexpected external calls are fatal.
        guard = r'''
APP_HOME="$STATE_DIR/home"
MODEL_CATALOG="testai/model-1"
LOG_DIR="$STATE_DIR/logs"
USER_BIN_DIR="$STATE_DIR/bin"
BACKUP_DIR="$STATE_DIR/backups"
OPENCODE_CONFIG_DIR="$STATE_DIR/opencode"
USER_SYSTEMD_DIR="$STATE_DIR/systemd"
SANDBOX_KNOWN_HOSTS_DIR="$STATE_DIR/known-hosts"
OPENCLAW_WORKSPACE="$APP_HOME/workspace"
require_root() { :; }
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) case "$1" in "$STATE_DIR"/*|"$STATE_DIR") mkdir -p "$1" ;; *) echo "unexpected install: $1" >&2; exit 91 ;; esac; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
id() { printf '1000\n'; }
resolve_openclaw_timezone() { OPENCLAW_TIMEZONE=UTC; }
'''
        for command in ('curl', 'ssh', 'ssh-keygen', 'ssh-keyscan', 'sudo', 'runuser',
                        'incus', 'systemctl', 'apt-get', 'openclaw', 'git', 'useradd'):
            guard += '\n' + command + '() { echo "unexpected external: ' + command + ' $*" >&2; exit 92; }\n'
        return self.run_vps_functions(guard + '\n' + body, state=state, extra_env=extra_env)

    def envfix_config(self, state):
        return json.loads((state / 'config/openclaw.json').read_text())

    # Fake credential is deliberately shell-hostile. It is sent only after the
    # PTY's hidden-input prompt, never as process argv or pre-echoed terminal input.
    github_sentinel = "ENVFIX_FAKE_ONLY_$`'\\\";$(touch SHOULD_NOT_EXIST) end"

    def bootstrap_fixture(self, initialize=True):
        if not (self.bin / 'openclaw').exists():
            had_calls = self.calls.exists()
            self.stub_envfix_openclaw()
            if not had_calls: self.calls.unlink()
        state = self.base / 'bootstrap'
        home = state / 'home'
        home.mkdir(parents=True, exist_ok=True)
        (home / 'workspace-dorian').mkdir(exist_ok=True)
        if initialize:
            (state / 'groups.json').write_text(json.dumps({'groups': [{'id': 'main', 'sshPort': 2222}]}))
            (state / 'agents.json').write_text(json.dumps({'agents': [{
                'id': 'dorian', 'group': 'main', 'default': True, 'label': 'Dorian',
                'workspace': str(home / 'workspace-dorian'),
                'agentDir': str(home / '.openclaw/agents/dorian/agent'), 'sandbox': {'mode': 'off'}}]}))
            (state / 'config.json').write_text(json.dumps({'agents': {'list': [{'id': 'dorian', 'sandbox': {'mode': 'off'}}]}}))
        (home / '.gitconfig').write_text('existing identity\n')
        for name in ('gh', 'git'):
            target = self.bin / name
            target.write_text(f'#!{sys.executable}\n' + r"""
import json, os, pathlib, sys, hashlib, subprocess
base = pathlib.Path(BASE)
a = sys.argv[1:]
with (base / 'auth-calls').open('a') as log:
    log.write(json.dumps({'tool': TOOL, 'args': a, 'env': dict(os.environ)}) + '\n')
home = pathlib.Path(os.environ['HOME'])
ghdir = home / '.config/gh'
hosts = ghdir / 'hosts.yml'
failure = (base / 'failure').read_text() if (base / 'failure').exists() else ''
def noisy_failure():
    # A CLI is permitted to repeat its input in errors; the parent must suppress it.
    if hosts.exists(): print(hosts.read_text(), file=sys.stderr)
    sys.exit(42)
if TOOL == 'gh':
    assert not any(k in os.environ for k in ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN', 'GH_DEBUG', 'GH_CONFIG_DIR', 'BASH_ENV', 'GIT_CONFIG_COUNT'))
    assert set(os.environ) <= {'HOME', 'PATH', 'LC_CTYPE', '__CF_USER_TEXT_ENCODING', 'GIT_TERMINAL_PROMPT'}, os.environ
    if str(home) == LOCAL_HOME:
        token_file = base / 'local-gh-token'
        if a == ['auth', 'token', '--hostname', 'github.com']:
            sys.exit(1) if not token_file.exists() else print(token_file.read_text())
        elif a == ['api', '--hostname', 'github.com', 'user', '--jq', '.login']:
            sys.exit(1) if (base / 'local-api-failure').exists() else print('offline-local-user')
        else: raise SystemExit('unexpected local gh command')
        sys.exit(0)
    if a == ['auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--with-token', '--insecure-storage']:
        token = sys.stdin.read().rstrip('\n')
        assert hashlib.sha256(token.encode()).hexdigest() == DIGEST
        ghdir.mkdir(parents=True, exist_ok=True)
        hosts.write_text(token)
        (ghdir / 'config.yml').write_text('new config')
        if failure == 'login': noisy_failure()
    elif a == ['auth', 'status', '--hostname', 'github.com']:
        sys.exit(0 if hosts.exists() and hosts.read_text() else 1)
    elif a == ['api', '--hostname', 'github.com', 'user', '--jq', '.login']:
        if failure == 'api' and hosts.exists(): noisy_failure()
        sys.exit(1) if not hosts.exists() else print('' if failure == 'empty-api' else 'offline-user')
    elif a == ['auth', 'setup-git', '--hostname', 'github.com']:
        (home / '.gitconfig').write_text('github helper configured')
        if failure == 'helper': noisy_failure()
    elif a == ['auth', 'git-credential', 'get']:
        assert sys.stdin.read() == 'protocol=https\nhost=github.com\n\n'
        if failure == 'credential': noisy_failure()
        print('username=offline-user\npassword=' + hosts.read_text())
    else: raise SystemExit('unexpected gh argv')
else:
    if a[:3] == ['config', '--global', '--get']:
        print('Existing identity')
    elif a == ['config', '--get-urlmatch', 'credential.helper', 'https://github.com']:
        if failure == 'resolution': sys.exit(1)
        assert 'helper configured' in (home / '.gitconfig').read_text()
        print('!' + GH + ' auth git-credential')
    elif a == ['credential', 'fill']:
        assert os.environ.get('GIT_TERMINAL_PROMPT') == '0', 'verification must never prompt'
        r = subprocess.run([GH, 'auth', 'git-credential', 'get'], input=sys.stdin.read(), text=True)
        sys.exit(r.returncode)
    else: raise SystemExit('unexpected git argv')
""".replace('BASE', repr(str(self.base))).replace('TOOL', repr(name)).replace('LOCAL_HOME', repr(str(self.home)))
                .replace('DIGEST', repr(hashlib.sha256(self.github_sentinel.encode()).hexdigest()))
                .replace('GH +', repr(str(self.bin / 'gh')) + ' +')
                .replace('[GH,', '[' + repr(str(self.bin / 'gh')) + ','))
            target.chmod(0o755)
        return state

    def bootstrap_run(self, state, *, tty=True, replace=False, ssh=False, trace=False, body='main github-bootstrap', via_manager=False, copy_local=False, stdin_text=''):
        source = (SCRIPTS / 'openclaw-vps.sh').read_text().rsplit('\nmain "$@"', 1)[0]
        overrides = r"""
STATE_DIR=STATE_VALUE
APP_HOME="$STATE_DIR/home"
APP_USER=openclaw
GROUPS_FILE="$STATE_DIR/groups.json"
AGENTS_FILE="$STATE_DIR/agents.json"
OPENCLAW_CONFIG_FILE="$STATE_DIR/config.json"
require_root() { :; }
chown() { printf 'chown %s\n' "$*" >> "$CALLS"; }
resolve_verified_host_tool() { printf '%s/%s\n' BIN_VALUE "$1"; }
seed_exec_allowlist() { printf 'approvals %s\n' "$*" >> "$CALLS"; }
prepare_github_ssh() { printf 'optional-ssh\n' >> "$CALLS"; }
sudo() {
    printf 'sudo %s\n' "$*" >> "$CALLS"
    case "$1" in
      -Hiu) [[ "$2" == openclaw && "$3" == -- ]] || return 98; shift 3 ;;
      -u) [[ "$2" == openclaw && "$3" == -H && "$4" == -- ]] || return 98; shift 4 ;;
      *) return 98 ;;
    esac
    # Simulate startup/PAM re-export AFTER switching users. The final env -i
    # must still remove every override before the executable receives it.
    (export HOME="$APP_HOME" GH_TOKEN=startup-poison GITHUB_TOKEN=startup-poison
     export GH_ENTERPRISE_TOKEN=startup-poison GITHUB_ENTERPRISE_TOKEN=startup-poison
     export GH_DEBUG=api GH_CONFIG_DIR=/must-not-use GIT_CONFIG_COUNT=99
     "$@")
}
""".replace('STATE_VALUE', shlex.quote(str(state))).replace('BIN_VALUE', shlex.quote(str(self.bin)))
        if via_manager:
            # Keep the real additive approvals implementation in the complete
            # flow; only its external CLI and ownership operations are stubbed.
            overrides = overrides.replace(
                'seed_exec_allowlist() { printf \'approvals %s\\n\' "$*" >> "$CALLS"; }',
                r"""
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
run_openclaw_local() {
  [[ "$(command -v openclaw)" == SAFE_OPENCLAW_PATH ]] || return 99
  env HOME="$APP_HOME" CALLS="$CALLS" OPENCLAW_STATE_DIR="$STATE_DIR/active state" PATH="$PATH" bash -c "$1"
}
""")
        overrides = overrides.replace('SAFE_OPENCLAW_PATH', shlex.quote(str(self.bin / 'openclaw')))
        script = source + overrides + ('\nset -x\n' if trace else '\n') + body
        if via_manager:
            remote = self.base / 'remote-bootstrap.sh'
            remote.write_text(source + overrides + ('\nset -x\n' if trace else '\n') + 'main "$@"\n')
            self.stub(self.bin / 'ssh',
                      'printf "%s\\n" "$@" >> "$CALLS"\n'
                      'read -r -a routed <<< "${@: -1}"\n'
                      '[[ "${routed[0]}" == /root/openclaw-vps.sh ]] || exit 99\n'
                      + 'exec ' + shlex.quote(test_bash()) + ' ' + shlex.quote(str(remote)) + ' "${routed[@]:1}"\n')
            script = 'exec ' + ' '.join(shlex.quote(x) for x in shell_command(
                str(SCRIPTS / 'agent-box-manage.sh'), 'github-bootstrap', '--box', 'test-box'))
        env = {k: self.env[k] for k in ('HOME', 'PATH', 'CALLS')}
        if not tty:
            return subprocess.run(shell_command('-c', script), env=env, input=stdin_text, text=True, capture_output=True, timeout=15)
        master, slave = pty.openpty()
        def terminal_session():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        proc = subprocess.Popen(shell_command('-c', script), stdin=slave, stdout=slave, stderr=slave,
                                env=env, preexec_fn=terminal_session, cwd=self.project)
        os.close(slave)
        output = b''
        sent = set()
        prompts = [(b'Copy local GitHub credentials', 'y' if copy_local else 'n'),
                   (b'Optional GitHub SSH setup', 'y' if ssh else 'n'),
                   (b'Replace existing GitHub login', 'y' if replace else 'n'),
                   (b'GitHub token (hidden): ', self.github_sentinel)]
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk: break
                    output += chunk
                    for prompt, answer in prompts:
                        if prompt in output and prompt not in sent:
                            if prompt.startswith(b'GitHub token'):
                                self.assertFalse(termios.tcgetattr(master)[3] & termios.ECHO,
                                                 'token prompt visible while terminal echo enabled')
                            os.write(master, (answer + '\n').encode())
                            sent.add(prompt)
                elif proc.poll() is not None:
                    break
            proc.wait(timeout=2)
        finally:
            if proc.poll() is None: proc.kill(); proc.wait()
            os.close(master)
        return subprocess.CompletedProcess([], proc.returncode, output.decode(errors='replace'), '')

    def assert_bootstrap_no_leak(self, *results):
        captured = ''.join(r.stdout + r.stderr for r in results)
        for path in [*self.base.glob('calls*'), self.base / 'auth-calls', *self.project.glob('*')]:
            if path.is_file(): captured += path.read_text()
        for path in ROOT.rglob('*.example*'):
            if path.is_file(): captured += path.read_text()
        for rendered in (self.github_sentinel, repr(self.github_sentinel), json.dumps(self.github_sentinel), shlex.quote(self.github_sentinel)):
            self.assertTrue(rendered not in captured, 'sentinel found in captured output/argv/examples/inventory')
        self.assertTrue(hashlib.sha256(self.github_sentinel.encode()).hexdigest() not in captured, 'sentinel digest found in capture')
        self.assertFalse((self.project / 'SHOULD_NOT_EXIST').exists())

    def test_envfix_github_bootstrap_setup_opt_out_and_opt_in(self):
        r = self.setup('OpenClaw', bot='', allow='')
        self.assertIn('GitHub', r.stderr)
        self.assertIn('OPENCLAW_GITHUB_BOOTSTRAP=0', (self.project / '.env').read_text())
        self.assertNotIn('github-bootstrap --box', r.stdout)
        self.assertFalse((self.home / '.config/gh').exists())
        (self.project / '.env').unlink(); (self.project / 'credentials.txt').unlink()
        r = self.setup('OpenClaw', bot='', allow='', github='y')
        self.assertIn('OPENCLAW_GITHUB_BOOTSTRAP=1', (self.project / '.env').read_text())
        self.assertIn('./agent-box-manage.sh github-bootstrap --box NAME', r.stdout)
        self.assertLess(r.stdout.index('register --runtime'), r.stdout.index('github-bootstrap --box'))
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_hermes_has_no_prompt(self):
        r = self.setup()
        self.assertNotIn('GitHub', r.stderr)
        self.assertNotIn('OPENCLAW_GITHUB_BOOTSTRAP', (self.project / '.env').read_text())

    def test_envfix_github_bootstrap_manager_direct_stdin_no_env_or_inventory_mutation(self):
        self.register('openclaw', agent='dorian')
        before = (self.project / 'boxes.json').read_bytes()
        (self.project / '.env').write_text('touch SHOULD_NOT_EXIST\n')
        self.stub(self.bin / 'ssh', 'printf "%s\\n" "$@" > "$CALLS"\ncat > "$CALLS.stdin"\nexit "${REMOTE_EXIT:-0}"\n')
        r = self.run_script(
            'agent-box-manage.sh', 'github-bootstrap', '--box', 'test-box', input='n\ninteractive-input\n')
        self.assertEqual(Path(str(self.calls) + '.stdin').read_text(), 'interactive-input\n')
        self.assertIn('-tt\n', self.calls.read_text())
        self.assertIn('root@100.64.0.10\n/root/openclaw-vps.sh github-bootstrap', self.calls.read_text())
        self.assertEqual(before, (self.project / 'boxes.json').read_bytes())
        self.env['REMOTE_EXIT'] = '23'
        failed = self.run_manager('github-bootstrap', ok=False)
        self.assertEqual(before, (self.project / 'boxes.json').read_bytes())
        self.assert_bootstrap_no_leak(r, failed)

    def test_envfix_github_bootstrap_manager_rejects_selectors_and_hermes(self):
        self.register('openclaw')
        for option in ('--agent', '--group'):
            r = self.run_manager('github-bootstrap', option, 'main', ok=False)
            self.assertIn('box-wide', r.stderr)
        (self.project / 'boxes.json').unlink()
        self.register('hermes')
        self.assertIn('OpenClaw', self.run_manager('github-bootstrap', ok=False).stderr)
        self.assertFalse(self.calls.exists())

    def test_envfix_github_bootstrap_no_tty_or_install_refuses_before_mutation(self):
        state = self.bootstrap_fixture()
        for tty in (False, True):
            if tty: (state / 'agents.json').unlink()
            r = self.bootstrap_run(state, tty=tty)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('terminal' if not tty else 'managed', r.stdout + r.stderr)
            self.assertFalse((state / 'home/.config').exists())
            self.assertFalse(self.calls.exists())

    def test_envfix_github_bootstrap_token_permissions_env_removal_and_second_invocation(self):
        state = self.bootstrap_fixture()
        r = self.bootstrap_run(state, trace=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        home = state / 'home'
        token = home / '.config/openclaw-vps/secrets/GH_TOKEN'
        hosts = home / '.config/gh/hosts.yml'
        self.assertTrue(token.read_text().rstrip('\n') == self.github_sentinel, 'token file did not preserve literal input')
        for path in (token, hosts, home / '.config/gh/config.yml'):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn('chown openclaw:openclaw ' + str(path), self.calls.read_text())
        for path in (token.parent, token.parent.parent, hosts.parent):
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        before = (token.read_bytes(), hosts.read_bytes())
        second = self.bootstrap_run(state)
        self.assertEqual(second.returncode, 0, second.stdout)
        self.assertTrue(before == (token.read_bytes(), hosts.read_bytes()), 'credential files changed on reuse')
        calls = [json.loads(line) for line in (self.base / 'auth-calls').read_text().splitlines()]
        self.assertEqual(sum(c['args'][:2] == ['auth', 'login'] for c in calls), 1)
        self.assertTrue(any(c['args'] == ['credential', 'fill'] for c in calls))
        self.assertNotIn('optional-ssh', self.calls.read_text())
        self.assertIn('approvals', self.calls.read_text())
        self.assert_bootstrap_no_leak(r, second)

    def test_envfix_github_bootstrap_existing_login_reuse_and_separate_ssh(self):
        state = self.bootstrap_fixture()
        ghdir = state / 'home/.config/gh'; ghdir.mkdir(parents=True)
        (ghdir / 'hosts.yml').write_text('OLD_VALID')
        r = self.bootstrap_run(state, ssh=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertTrue((ghdir / 'hosts.yml').read_text() == 'OLD_VALID', 'existing login changed')
        self.assertFalse((state / 'home/.config/openclaw-vps/secrets/GH_TOKEN').exists())
        self.assertIn('optional-ssh', self.calls.read_text())
        self.assertNotIn('GitHub token (hidden)', r.stdout)
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_failure_rollback_and_retry(self):
        for failure in ('login', 'helper', 'api', 'empty-api', 'credential', 'resolution'):
            with self.subTest(failure=failure):
                state = self.bootstrap_fixture()
                ghdir = state / 'home/.config/gh'; ghdir.mkdir(parents=True, exist_ok=True)
                (ghdir / 'hosts.yml').write_text('OLD_VALID')
                (ghdir / 'config.yml').write_text('old config')
                token = state / 'home/.config/openclaw-vps/secrets/GH_TOKEN'
                token.parent.mkdir(parents=True, exist_ok=True); token.write_text('OLD_TOKEN')
                (self.base / 'failure').write_text(failure)
                before = {p: p.read_bytes() for p in (ghdir / 'hosts.yml', ghdir / 'config.yml', token, state / 'home/.gitconfig', state / 'agents.json', state / 'config.json')}
                r = self.bootstrap_run(state, replace=True, trace=True)
                self.assertNotEqual(r.returncode, 0, r.stdout)
                self.assertIn('failed', r.stdout.lower())
                for p, data in before.items(): self.assertTrue(p.read_bytes() == data, 'rollback mismatch: ' + str(p))
                self.assertFalse(list(token.parent.glob('.github-*')))
                self.assert_bootstrap_no_leak(r)
                (self.base / 'failure').unlink()
                retry = self.bootstrap_run(state, replace=True)
                self.assertEqual(retry.returncode, 0, retry.stdout)
                self.assert_bootstrap_no_leak(retry)

    def test_envfix_github_bootstrap_existing_api_failure_requires_explicit_replacement(self):
        state = self.bootstrap_fixture()
        ghdir = state / 'home/.config/gh'; ghdir.mkdir(parents=True)
        (ghdir / 'hosts.yml').write_text('OLD_VALID')
        (self.base / 'failure').write_text('api')
        r = self.bootstrap_run(state)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('Replace existing GitHub login', r.stdout)
        self.assertNotIn('GitHub token (hidden)', r.stdout)
        self.assertTrue((ghdir / 'hosts.yml').read_text() == 'OLD_VALID', 'existing login changed')
        calls = [json.loads(line) for line in (self.base / 'auth-calls').read_text().splitlines()]
        self.assertFalse(any(c['args'][:2] == ['auth', 'login'] for c in calls))
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_failed_first_login_leaves_no_credentials(self):
        state = self.bootstrap_fixture()
        (self.base / 'failure').write_text('api')
        r = self.bootstrap_run(state)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('failed', r.stdout.lower())
        self.assertFalse((state / 'home/.config/gh/hosts.yml').exists())
        self.assertFalse((state / 'home/.config/openclaw-vps/secrets/GH_TOKEN').exists())
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_private_transfer_preserves_existing_token(self):
        state = self.bootstrap_fixture()
        secret_dir = state / 'home/.config/openclaw-vps/secrets'
        secret_dir.mkdir(parents=True)
        token = secret_dir / 'GH_TOKEN'; token.write_text('OLD_TOKEN')
        staged = secret_dir / '.GH_TOKEN.import.Abc123'
        r = self.bootstrap_run(state, tty=False, body='main github-token-stage Abc123', stdin_text=self.github_sentinel)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(staged.read_text() == self.github_sentinel, 'copied token changed in transit')
        self.assertTrue(token.read_text() == 'OLD_TOKEN', 'transfer overwrote existing credential')
        self.assertEqual(staged.stat().st_mode & 0o777, 0o600)
        self.assertEqual(secret_dir.stat().st_mode & 0o777, 0o700)
        self.assertIn('chown openclaw:openclaw', self.calls.read_text())
        discarded = self.bootstrap_run(state, tty=False, body='main github-token-discard Abc123')
        self.assertEqual(discarded.returncode, 0, discarded.stderr)
        self.assertFalse(staged.exists())
        outside = self.base / 'outside-transfer'; outside.write_text('untouched')
        staged.symlink_to(outside)
        refused = self.bootstrap_run(state, tty=False, body='main github-token-stage Abc123', stdin_text=self.github_sentinel)
        self.assertNotEqual(refused.returncode, 0)
        self.assertEqual(outside.read_text(), 'untouched')
        self.assert_bootstrap_no_leak(r, discarded, refused)

    def test_envfix_github_bootstrap_copy_local_credentials_without_token_echo(self):
        self.register('openclaw', agent='dorian')
        state = self.bootstrap_fixture()
        (self.base / 'local-gh-token').write_text(self.github_sentinel)
        (self.project / '.env').write_text('touch SHOULD_NOT_EXIST\n')
        before = (self.project / 'boxes.json').read_bytes()
        r = self.bootstrap_run(state, via_manager=True, copy_local=True, trace=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn('Copy local GitHub credentials', r.stdout)
        self.assertNotIn('GitHub token (hidden)', r.stdout)
        self.assertIn('github-token-stage', self.calls.read_text())
        self.assertIn('github-bootstrap --import-id', self.calls.read_text())
        self.assertEqual(before, (self.project / 'boxes.json').read_bytes())
        self.assertTrue((state / 'home/.config/openclaw-vps/secrets/GH_TOKEN').read_text().strip() == self.github_sentinel)
        self.assertFalse(list((state / 'home/.config/openclaw-vps/secrets').glob('.GH_TOKEN.import.*')))
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_no_working_local_credential_falls_back_to_manual(self):
        self.register('openclaw', agent='dorian')
        for invalid in ('missing', 'api'):
            with self.subTest(invalid=invalid):
                state = self.bootstrap_fixture()
                if (state / 'home/.config').exists(): shutil.rmtree(state / 'home/.config')
                if invalid == 'api':
                    (self.base / 'local-gh-token').write_text(self.github_sentinel)
                    (self.base / 'local-api-failure').write_text('fail')
                r = self.bootstrap_run(state, via_manager=True, copy_local=True)
                self.assertEqual(r.returncode, 0, r.stdout)
                self.assertIn('manual entry', r.stdout)
                self.assertIn('GitHub token (hidden)', r.stdout)
                self.assertNotIn('github-token-stage', self.calls.read_text())
                self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_copied_replacement_rolls_back(self):
        self.register('openclaw', agent='dorian')
        state = self.bootstrap_fixture()
        ghdir = state / 'home/.config/gh'; ghdir.mkdir(parents=True)
        (ghdir / 'hosts.yml').write_text('OLD_VALID')
        (self.base / 'local-gh-token').write_text(self.github_sentinel)
        (self.base / 'failure').write_text('api')
        r = self.bootstrap_run(state, via_manager=True, copy_local=True, replace=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('GitHub token (hidden)', r.stdout)
        self.assertTrue((ghdir / 'hosts.yml').read_text() == 'OLD_VALID', 'copied replacement changed existing login')
        self.assertFalse((state / 'home/.config/openclaw-vps/secrets/GH_TOKEN').exists())
        self.assertFalse(list((state / 'home/.config/openclaw-vps/secrets').glob('.GH_TOKEN.import.*')))
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_terminal_restore_failure_still_cleans_up(self):
        state = self.bootstrap_fixture()
        r = self.bootstrap_run(state, body=r'''
stty() { case "$1" in -g|-echo) command stty "$@" ;; *) return 1 ;; esac; }
main github-bootstrap
''')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((state / 'home/.config/openclaw-vps/secrets/.github-bootstrap.lock').exists())
        self.assertFalse((state / 'home/.config/openclaw-vps/secrets/GH_TOKEN').exists())
        self.assert_bootstrap_no_leak(r)

    def test_envfix_github_bootstrap_rejects_incomplete_managed_config(self):
        state = self.bootstrap_fixture()
        (state / 'config.json').write_text('{"agents":{"list":[]}}')
        r = self.bootstrap_run(state)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('managed', r.stdout)
        self.assertFalse((state / 'home/.config').exists())
        self.assertFalse(self.calls.exists())

    def test_envfix_github_bootstrap_full_offline_flow(self):
        setup = self.setup('OpenClaw', bot='', allow='', github='y', initial_label="Dorian's lab")
        self.stub_scp_and_capture_ssh()
        forwarded = self.run_hetzner_functions('. ' + shlex.quote(str(self.project / '.env')) + '\nwrite_remote_env_file')
        self.assertEqual(forwarded.returncode, 0, forwarded.stderr)
        transport = Path(str(self.calls) + '.stdin')
        values = subprocess.check_output(shell_command('-c',
            '. "$1"; printf "%s\\n" "$OPENCLAW_INITIAL_AGENT_ID" "$OPENCLAW_INITIAL_AGENT_LABEL"',
            'bash', str(transport)), env=self.env, text=True).splitlines()
        self.assertEqual(values, ['dorian', "Dorian's lab"])
        self.assertNotIn('GH_TOKEN', transport.read_text())
        state = self.base / 'bootstrap'
        self.stub_envfix_openclaw()
        installed = self.run_vps_functions(r'''
APP_HOME="$STATE_DIR/home"
BACKUP_DIR="$STATE_DIR/backups"
OPENCLAW_CONFIG_FILE="$STATE_DIR/config.json"
SANDBOX_SSH_KEY="$APP_HOME/.ssh/openclaw-sandbox_ed25519"
SANDBOX_KNOWN_HOSTS_DIR="$APP_HOME/.ssh/openclaw-sandbox-known-hosts"
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR" "$USER_CONFIG_DIR"
printf 'OPENCLAW_STATE_DIR=%q\n' "$STATE_DIR/active state" > "$USER_ENV_FILE"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[]}\n' > "$AGENTS_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
sync_agent_workspace_skills() { :; }
resolve_verified_host_tool() { printf '%s/%s\n' "$USER_BIN_DIR" "$1"; }
ensure_agent "$DEFAULT_AGENT_ID" main "" "" "$OPENCLAW_INITIAL_AGENT_LABEL" true
regenerate_openclaw_config
seed_exec_allowlist fresh
ensure_workspace_host_action_notes
''', state=state, extra_env={'ENVFIX_REAL_EXEC': '1',
                            'OPENCLAW_INITIAL_AGENT_ID': values[0],
                            'OPENCLAW_INITIAL_AGENT_LABEL': values[1]})
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
        notes = (state / 'home/workspace-dorian/TOOLS.md').read_text()
        for phrase in ('argument allowlist', 'prompting disabled', 'fail closed', 'git', 'gh', 'openclaw approvals allowlist', 'operator', 'bypass'):
            self.assertIn(phrase, notes)
        agents = json.loads((state / 'agents.json').read_text())['agents']
        config = json.loads((state / 'config.json').read_text())
        approvals = state / 'active state/active-approvals.json'
        grants = json.loads(approvals.read_text())
        self.assertEqual([a['id'] for a in agents], ['dorian'])
        self.assertEqual(config['agents']['list'][0]['workspace'], agents[0]['workspace'])
        self.assertEqual(grants['agents']['*']['allowlist'], [{'pattern': str(self.bin / 'git')}, {'pattern': str(self.bin / 'gh')}])
        grants['defaults'] = {'security': 'deny', 'ask': 'always'}
        approvals.write_text(json.dumps(grants))
        registered = self.register('openclaw', agent=agents[0]['id'], group=agents[0]['group'])
        self.assertEqual(self.state()['version'], 1)
        self.assertEqual(self.state()['boxes'][0]['agents'], [{'id': 'dorian', 'group': 'main'}])
        before = {p: p.read_bytes() for p in [self.project / 'boxes.json', state / 'agents.json', state / 'config.json', approvals]}
        self.bootstrap_fixture(initialize=False)
        bootstrapped = self.bootstrap_run(state, via_manager=True, trace=True)
        self.assertEqual(bootstrapped.returncode, 0, bootstrapped.stdout)
        for path, data in before.items(): self.assertEqual(path.read_bytes(), data)
        self.assertEqual(self.calls.read_text().count('openclaw approvals allowlist add --agent *'), 4)
        self.assertIn('root@100.64.0.10', self.calls.read_text())
        self.assertIn('verified without token environment variables', bootstrapped.stdout)
        # The secret is allowed only in the two explicitly private credential
        # stores. Audit all other generated state too, not just terminal logs.
        for path in state.rglob('*'):
            if path.is_file() and path.name not in ('GH_TOKEN', 'hosts.yml'):
                self.assertTrue(self.github_sentinel.encode() not in path.read_bytes(), 'sentinel found in ' + str(path))
        self.assert_bootstrap_no_leak(setup, forwarded, installed, registered, bootstrapped)

    def test_envfix_github_bootstrap_symlink_refusal(self):
        for relative in ('.config', '.config/gh', '.config/gh/hosts.yml', '.gitconfig', '.config/git/config',
                         '.config/openclaw-vps/secrets', '.config/openclaw-vps/secrets/GH_TOKEN'):
            with self.subTest(path=relative):
                state = self.bootstrap_fixture()
                path = state / 'home' / relative
                if path.is_dir(): shutil.rmtree(path)
                elif path.exists(): path.unlink()
                path.parent.mkdir(parents=True, exist_ok=True)
                outside = self.base / 'outside'; outside.write_text('untouched')
                path.symlink_to(outside)
                try:
                    r = self.bootstrap_run(state)
                finally:
                    path.unlink()
                self.assertNotEqual(r.returncode, 0)
                self.assertIn('symlink', r.stdout)
                self.assertEqual(outside.read_text(), 'untouched')

    def github_identity_run(self, body, state=None, input_text='', extra_env=None):
        state = state or (self.base / 'github-identity')
        guard = r'''
APP_HOME="$STATE_DIR/home"
APP_USER=openclaw
GITHUB_SSH_DIR="$APP_HOME/.ssh"
GITHUB_SSH_KEY="$GITHUB_SSH_DIR/github_ed25519"
GITHUB_SSH_PUBLIC_KEY="$GITHUB_SSH_KEY.pub"
GITHUB_SSH_CONFIG="$GITHUB_SSH_DIR/config"
GITHUB_KNOWN_HOSTS="$GITHUB_SSH_DIR/known_hosts"
GIT_STORE="$STATE_DIR/git-config"
mkdir -p "$STATE_DIR" "$APP_HOME"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { printf 'chown %s\n' "$*" >> "$CALLS"; }
chmod() { printf 'chmod %s\n' "$*" >> "$CALLS"; /bin/chmod "$@"; }
sudo() {
    printf 'sudo %s\n' "$*" >> "$CALLS"
    [[ "$1" == -Hiu && "$2" == openclaw && "$3" == -- ]] || { echo "unexpected sudo $*" >&2; return 97; }
    shift 3
    "$@"
}
git() {
    local arg key value
    printf 'git %s\n' "$*" >> "$CALLS"
    for arg in "$@"; do printf 'git-arg=%s\n' "$arg" >> "$CALLS"; done
    if [[ "$1" == config && "$2" == --global && "$3" == --get ]]; then
        key="$4"
        [[ -f "$GIT_STORE.$key" ]] || return 1
        cat "$GIT_STORE.$key"
        return 0
    fi
    if [[ "$1" == config && "$2" == --global && "$#" == 4 ]]; then
        key="$3"
        value="$4"
        printf '%s' "$value" > "$GIT_STORE.$key"
        return 0
    fi
    echo "unexpected git $*" >&2
    return 98
}
ssh-keyscan() {
    printf 'ssh-keyscan %s\n' "$*" >> "$CALLS"
    printf '%s\n' \
      'github.com ssh-ed25519 AAAA_ED25519 github.com' \
      'github.com ssh-rsa AAAA_RSA github.com'
}
ssh-keygen() {
    local path
    printf 'ssh-keygen %s\n' "$*" >> "$CALLS"
    if [[ "$1" == -y && "$2" == -f ]]; then
        printf '%s\n' 'ssh-ed25519 AAAA_ED25519 github-bootstrap'
        return 0
    fi
    if [[ "$1" == -lf ]]; then
        path="$2"
        if [[ "$path" == *github-keyscan* ]]; then
            printf '256 SHA256:+DiY3wvvV6TuJJhbpZisF/o8t4U7AqW5 github.com (ED25519)\n'
            printf '3072 SHA256:nThbg6kXUpJWGlmIJbZL github.com (RSA)\n'
        else
            printf '256 SHA256:+DiY3wvvV6TuJJhbpZisF/o8t4U7AqW5 github.com (ED25519)\n'
        fi
        return 0
    fi
    if [[ "$1" == -q && "$2" == -t ]]; then
        path="$9"
        printf '%s\n' 'PRIVATE-KEY-GENERATED' > "$path"
        printf '%s\n' 'ssh-ed25519 AAAA_ED25519 github-bootstrap' > "$path.pub"
        return 0
    fi
    echo "unexpected ssh-keygen $*" >&2
    return 99
}
'''
        return self.run_vps_functions(guard + '\n' + body, state=state,
                                      extra_env=dict(ENVFIX_REAL_EXEC='1', **(extra_env or {})),
                                      input_text=input_text)

    def test_envfix_github_identity_missing_git_settings_prompt_and_literal_transport(self):
        result = self.github_identity_run(
            'ensure_git_identity\n',
            input_text='Ada "Quote" O\'Neil\nada+tag@example.test\nfeature branch\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.base / 'github-identity'
        self.assertEqual((state / 'git-config.user.name').read_text(), 'Ada "Quote" O\'Neil')
        self.assertEqual((state / 'git-config.user.email').read_text(), 'ada+tag@example.test')
        self.assertEqual((state / 'git-config.init.defaultBranch').read_text(), 'feature branch')
        calls = self.calls.read_text()
        self.assertIn('sudo -Hiu openclaw -- git config --global user.name Ada "Quote" O\'Neil', calls)
        self.assertIn('git-arg=Ada "Quote" O\'Neil', calls)
        self.assertFalse((state / 'SHOULD_NOT_EXIST').exists())

    def test_envfix_github_identity_existing_settings_are_preserved_without_prompts(self):
        state = self.base / 'github-existing'
        body = r'''
printf '%s' 'Ada "Quote" O'\''Neil' > "$GIT_STORE.user.name"
printf '%s' 'ada+tag@example.test' > "$GIT_STORE.user.email"
printf '%s' 'feature branch' > "$GIT_STORE.init.defaultBranch"
ensure_git_identity
'''
        result = self.github_identity_run(body, state=state, input_text='SHOULD_NOT_BE_READ\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((state / 'git-config.user.name').read_text(), 'Ada "Quote" O\'Neil')
        self.assertEqual((state / 'git-config.user.email').read_text(), 'ada+tag@example.test')
        self.assertEqual((state / 'git-config.init.defaultBranch').read_text(), 'feature branch')
        calls = self.calls.read_text()
        self.assertNotIn('git-arg=SHOULD_NOT_BE_READ', calls)
        self.assertNotIn('git config --global user.name', calls)
        self.assertNotIn('git config --global user.email', calls)
        self.assertNotIn('git config --global init.defaultBranch', calls)

    def test_envfix_github_identity_reuses_key_and_recovers_missing_public_key(self):
        for missing_public in (False, True):
            with self.subTest(missing_public=missing_public):
                self.calls.unlink(missing_ok=True)
                state = self.base / ('github-key-missing-pub' if missing_public else 'github-key-reuse')
                body = r'''
mkdir -p "$GITHUB_SSH_DIR"
printf '%s\n' 'PRIVATE-KEY-KEEP' > "$GITHUB_SSH_KEY"
''' + ('' if missing_public else r'''printf '%s\n' 'ssh-ed25519 AAAA_ED25519 github-bootstrap' > "$GITHUB_SSH_PUBLIC_KEY"
''') + r'''
prepare_github_ssh
'''
                result = self.github_identity_run(body, state=state)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((state / 'home/.ssh/github_ed25519').read_text(), 'PRIVATE-KEY-KEEP\n')
                self.assertTrue((state / 'home/.ssh/github_ed25519.pub').is_file())
                self.assertNotIn('PRIVATE-KEY-KEEP', result.stdout + result.stderr + self.calls.read_text())

    def test_envfix_github_identity_refuses_symlink_outputs_and_parents(self):
        for variant in ('parent', 'key', 'config', 'known_hosts'):
            with self.subTest(variant=variant):
                self.calls.unlink(missing_ok=True)
                state = self.base / ('github-symlink-' + variant)
                body = r'''
mkdir -p "$APP_HOME/.ssh" "$STATE_DIR/real"
'''
                if variant == 'parent':
                    body = r'''
mkdir -p "$APP_HOME" "$STATE_DIR/real"
ln -s "$STATE_DIR/real" "$APP_HOME/.ssh"
'''
                elif variant == 'key':
                    body += r'''
ln -s "$STATE_DIR/real/key" "$GITHUB_SSH_KEY"
'''
                elif variant == 'config':
                    body += r'''
ln -s "$STATE_DIR/real/config" "$GITHUB_SSH_CONFIG"
'''
                else:
                    body += r'''
ln -s "$STATE_DIR/real/known_hosts" "$GITHUB_KNOWN_HOSTS"
'''
                body += 'prepare_github_ssh\n'
                result = self.github_identity_run(body, state=state)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('symlink', result.stderr.lower())

    def test_envfix_github_identity_rejects_conflicting_github_config(self):
        state = self.base / 'github-config-conflict'
        body = r'''
mkdir -p "$GITHUB_SSH_DIR"
printf '%s\n' 'Host github.com' '  IdentityFile ~/.ssh/other_ed25519' > "$GITHUB_SSH_CONFIG"
printf '%s\n' 'Host example.test' '  User unrelated' >> "$GITHUB_SSH_CONFIG"
prepare_github_ssh
'''
        result = self.github_identity_run(body, state=state)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('conflicting', result.stderr.lower())
        self.assertEqual((state / 'home/.ssh/config').read_text(),
                         'Host github.com\n  IdentityFile ~/.ssh/other_ed25519\nHost example.test\n  User unrelated\n')
        self.assertNotIn('ssh-keyscan', self.calls.read_text())

    def test_envfix_github_identity_rejects_unknown_host_fingerprint_before_known_hosts_write(self):
        state = self.base / 'github-fingerprint-mismatch'
        body = r'''
ssh-keygen() {
    if [[ "$1" == -lf ]]; then
        printf '256 SHA256:unknown-github-key github.com (ED25519)\n'
        return 0
    fi
    echo "unexpected ssh-keygen $*" >&2
    return 99
}
prepare_github_ssh
'''
        result = self.github_identity_run(body, state=state)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('fingerprint', result.stderr.lower())
        self.assertFalse((state / 'home/.ssh/known_hosts').exists())

    def test_envfix_github_identity_repeat_run_is_byte_stable_and_marked(self):
        state = self.base / 'github-repeat'
        body = r'''
mkdir -p "$GITHUB_SSH_DIR"
if [[ ! -e "$GITHUB_SSH_KEY" ]]; then
    printf '%s\n' 'PRIVATE-KEY-STABLE' > "$GITHUB_SSH_KEY"
fi
prepare_github_ssh
'''
        first = self.github_identity_run(body, state=state)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        paths = [state / 'home/.ssh/github_ed25519', state / 'home/.ssh/github_ed25519.pub',
                 state / 'home/.ssh/config', state / 'home/.ssh/known_hosts']
        before = [path.read_bytes() for path in paths]
        second = self.github_identity_run(body, state=state)
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(before, [path.read_bytes() for path in paths])
        config = paths[2].read_text()
        self.assertEqual(config.count('# openclaw-vps github-bootstrap'), 1)
        self.assertEqual(config.count('# end openclaw-vps github-bootstrap'), 1)
        self.assertEqual(paths[3].read_text().count('github.com ssh-ed25519'), 1)
        self.assertEqual(paths[3].read_text().count('github.com ssh-rsa'), 1)
        output = first.stdout + first.stderr + second.stdout + second.stderr
        self.assertNotIn('PRIVATE-KEY-STABLE', output)
        self.assertIn('ssh-ed25519', output)
        self.assertIn('SHA256:', output)

    def test_envfix_workspace_custom_sync_prune_notes_and_default(self):
        state = self.envfix_fixture()
        records = json.loads((state / 'agents.json').read_text())
        workspace = state / 'custom workspace'
        records['agents'][0]['workspace'] = str(workspace)
        (state / 'agents.json').write_text(json.dumps(records))
        source = state / 'home/.agents/skills/example'
        source.mkdir(parents=True)
        (source / 'SKILL.md').write_text('example')
        stale = workspace / 'skills/stale'
        stale.mkdir(parents=True)
        (stale / '.openclaw-vps-managed-skill').touch()
        result = self.envfix_run(state, 'regenerate_openclaw_config\nensure_workspace_host_action_notes')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((workspace / 'skills/example/SKILL.md').exists())
        self.assertFalse(stale.exists())
        self.assertIn(str(workspace), (workspace / 'TOOLS.md').read_text())
        config = self.envfix_config(state)
        self.assertEqual(config['agents']['defaults']['workspace'], str(workspace))
        self.assertEqual(config['agents']['list'][0]['workspace'], str(workspace))
        self.assertFalse((state / 'home/workspace-dorian').exists())

    def test_envfix_proxy_safe_cli_wrappers_install_and_refresh(self):
        state = self.envfix_fixture()
        body = r'''
mkdir -p "$USER_BIN_DIR" \
  "$APP_HOME/.local/lib/node_modules/@openai/codex/bin" \
  "$APP_HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin" \
  "$APP_HOME/.local/lib/node_modules/opencode-ai/bin"
for real in "$APP_HOME/.local/lib/node_modules/@openai/codex/bin/codex.js" \
  "$APP_HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" \
  "$APP_HOME/.local/lib/node_modules/opencode-ai/bin/opencode.exe"; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$real"
done
install_proxy_safe_cli_wrappers
install_proxy_safe_cli_wrappers
'''
        result = self.envfix_run(state, body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name, relative in (
                ('codex', '@openai/codex/bin/codex.js'),
                ('claude', '@anthropic-ai/claude-code/bin/claude.exe'),
                ('opencode', 'opencode-ai/bin/opencode.exe')):
            wrapper = state / 'bin' / name
            self.assertTrue(wrapper.is_file(), wrapper)
            text = wrapper.read_text()
            self.assertIn('openclaw-vps managed proxy-safe wrapper', text)
            self.assertIn(str(state / 'home/.local/lib/node_modules' / relative), text)
            self.assertIn('exec env -u HTTP_PROXY -u HTTPS_PROXY', text)
            self.assertIn('-u SSL_CERT_FILE', text)
            self.assertEqual(text.count('#!'), 1)
        self.assertEqual(list((state / 'bin').glob('.proxy-safe-*')), [])
        self.assertIn('proxy-safe wrapper installed', result.stdout)

    def test_envfix_proxy_safe_cli_wrappers_respect_operator_shims(self):
        state = self.envfix_fixture()
        body = r'''
mkdir -p "$USER_BIN_DIR"
printf '#!/usr/bin/env sh\necho operator codex shim\n' > "$USER_BIN_DIR/codex"
printf '#!/usr/bin/env bash\nexec env -u HTTPS_PROXY /bin/true "$@"\n' > "$USER_BIN_DIR/opencode-foreign"
mkdir -p "$APP_HOME/.local/lib/node_modules/@openai/codex/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$APP_HOME/.local/lib/node_modules/@openai/codex/bin/codex.js"
run_as_app_user() {
  case "$1" in
    "command -v claude") return 1 ;;
    "command -v opencode") printf '%s\n' "$USER_BIN_DIR/opencode-foreign" ;;
    "readlink -f"*) printf '%s\n' "${1#readlink -f }" ;;
    *) return 1 ;;
  esac
}
install_proxy_safe_cli_wrappers
'''
        result = self.envfix_run(state, body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = result.stdout + result.stderr
        self.assertIn('codex is operator-owned', output)
        self.assertIn('claude is not installed', output)
        self.assertIn('already has', output)
        self.assertEqual((state / 'bin' / 'codex').read_text(),
                         '#!/usr/bin/env sh\necho operator codex shim\n')
        self.assertFalse((state / 'bin' / 'claude').exists())
        self.assertFalse((state / 'bin' / 'opencode').exists())

    def test_envfix_tools_md_documents_proxy_safe_wrappers_once(self):
        state = self.envfix_fixture()
        result = self.envfix_run(state, 'regenerate_openclaw_config\n'
                                      'ensure_workspace_host_action_notes\n'
                                      'ensure_workspace_host_action_notes')
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = (state / 'home/workspace-dorian/TOOLS.md').read_text()
        self.assertEqual(notes.count('## Proxy-Safe CLI Wrappers'), 1)
        self.assertIn('gateway secret-egress proxy and CA', notes)
        self.assertIn('Do not bypass, edit, or shadow these wrappers', notes)
        self.assertIn('407s', notes)

    def test_proxy_safe_cli_wrapper_wiring(self):
        source = (SCRIPTS / 'openclaw-vps.sh').read_text()
        self.assertEqual(source.count('install_proxy_safe_cli_wrappers() {'), 1)
        self.assertIn('  install_openclaw_and_opencode\n'
                      '  install_proxy_safe_cli_wrappers\n'
                      '  ensure_git_gh_installed || return 1', source)
        self.assertIn('  write_helper_scripts\n'
                      '  install_proxy_safe_cli_wrappers\n'
                      '  restart_openclaw_gateway', source)
        self.assertIn('Proxy-Safe CLI Wrappers', source)

    def test_envfix_workspace_fresh_no_fallback_and_file_tool_configuration_contract(self):
        """Offline configuration contract, not a live OpenClaw file-tool test."""
        state = self.envfix_fixture(agents=[])
        result = self.envfix_run(state, 'ensure_app_user\nensure_agent dorian main "" "" Dorian true\nregenerate_openclaw_config')
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.envfix_config(state)
        workspace = Path(config['agents']['list'][0]['workspace'])
        self.assertEqual(config['agents']['defaults']['workspace'], str(workspace))
        self.assertEqual(config['tools']['exec']['host'], 'gateway')
        self.assertEqual(config['agents']['list'][0]['sandbox'], {'mode': 'off'})
        for session in range(2):
            # Simulated file tool uses configured workspace; simulated exec uses it as cwd.
            (workspace / 'marker').write_text('persistent' if session == 0 else (workspace / 'marker').read_text())
            read = subprocess.run(shell_command('-c', 'cat marker'), cwd=workspace,
                                  text=True, capture_output=True, check=True)
            self.assertEqual(read.stdout, 'persistent')
        self.assertFalse((state / 'home/workspace').exists())
        self.assertFalse((state / 'home/.openclaw/workspace-dorian').exists())

    def test_envfix_workspace_duplicate_preserved_and_canonical_alias_allowed(self):
        state = self.envfix_fixture()
        duplicate = state / 'home/.openclaw/workspace-dorian'
        duplicate.mkdir(parents=True)
        marker = duplicate / 'unique-work'
        marker.write_text('never delete')
        before = (state / 'agents.json').read_bytes()
        result = self.envfix_run(state)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate workspace', result.stderr)
        self.assertIn(str(duplicate), result.stderr)
        self.assertEqual(marker.read_text(), 'never delete')
        self.assertEqual((state / 'agents.json').read_bytes(), before)
        self.assertFalse((duplicate / '.git').exists())
        self.assertFalse((state / 'home/workspace-dorian').exists())
        marker.unlink()
        duplicate.rmdir()
        canonical = state / 'home/workspace-dorian'
        canonical.mkdir()
        duplicate.symlink_to(canonical, target_is_directory=True)
        result = self.envfix_run(state)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_envfix_workspace_invalid_later_path_is_atomic(self):
        state = self.envfix_fixture()
        rows = json.loads((state / 'agents.json').read_text())['agents']
        rows.append(self.envfix_agent(state, 'second', sandbox={'mode': 'off'}))
        rows[1]['workspace'] = 'relative/path'
        (state / 'agents.json').write_text(json.dumps({'agents': rows}))
        result = self.envfix_run(state)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('workspace', result.stderr)
        self.assertFalse((state / 'home').exists())

    def test_envfix_sandbox_legacy_full_policy_list_entries_and_manual_off(self):
        ssh = {'mode': 'all', 'backend': 'ssh', 'scope': 'session', 'workspaceAccess': 'rw',
               'ssh': {'target': 'other@127.0.0.1:2233', 'identityFile': '/keys/legacy',
                       'knownHostsFile': '/keys/hosts', 'workspaceRoot': '/persist'},
               'browser': {'enabled': False}, 'containers': {'keep': True}}
        for shape in ('list', 'entries'):
            for mode in ('all', 'off'):
                with self.subTest(shape=shape, mode=mode):
                    state = self.envfix_fixture(agents=[])
                    rows = [self.envfix_agent(state, 'dorian')]
                    (state / 'agents.json').write_text(json.dumps({'agents': rows}))
                    entry = {'id': 'dorian', 'sandbox': {'mode': mode, 'ssh': {'workspaceRoot': '/custom'}}}
                    agents = {'defaults': {'sandbox': ssh}, shape: [entry] if shape == 'list' else {'dorian': entry}}
                    (state / 'config/openclaw.json').write_text(json.dumps({'agents': agents}))
                    before = (state / 'agents.json').read_bytes()
                    result = self.envfix_run(state)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    expected = dict(ssh, mode=mode, ssh=dict(ssh['ssh'], workspaceRoot='/custom'))
                    self.assertEqual(self.envfix_config(state)['agents']['list'][0]['sandbox'], expected)
                    self.assertEqual((state / 'agents.json').read_bytes(), before)

    def test_envfix_sandbox_managed_override_independent_of_tools(self):
        state = self.envfix_fixture(config={'agents': {'list': [{'id': 'dorian', 'sandbox': {'mode': 'all'}}]}})
        result = self.envfix_run(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['agents']['list'][0]['sandbox'], {'mode': 'off'})

    def test_envfix_sandbox_invalid_or_unresolved_policy_atomicity(self):
        for policy in (None, 'off', {}, {'mode': 'mystery'}, {'mode': 'all', 'backend': 'mystery'},
                       {'mode': 'off', 'ssh': []}, {'mode': 'off', 'browser': {'enabled': 'yes'}}):
            for entrypoint in ('regenerate_openclaw_config', 'cmd_refresh_config', 'ensure_agent new main token 123'):
                with self.subTest(policy=policy, entrypoint=entrypoint):
                    state = self.envfix_fixture()
                    rows = json.loads((state / 'agents.json').read_text())['agents']
                    bad = self.envfix_agent(state, 'second')
                    if policy is not None:
                        bad['sandbox'] = policy
                    rows.append(bad)
                    (state / 'agents.json').write_text(json.dumps({'agents': rows}))
                    config = state / 'config/openclaw.json'
                    config.write_text('{"sentinel":true}')
                    before = {p: p.read_bytes() for p in state.rglob('*') if p.is_file()}
                    result = self.envfix_run(state, entrypoint)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('sandbox', result.stderr)
                    self.assertEqual({p: p.read_bytes() for p in state.rglob('*') if p.is_file()}, before)
                    self.assertFalse((state / 'home').exists())
        state = self.envfix_fixture(agents=[])
        (state / 'agents.json').write_text(json.dumps({'agents': [self.envfix_agent(state, 'old')]}))
        result = self.envfix_run(state)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('sandbox', result.stderr)
        self.assertFalse((state / 'config/openclaw.json').exists())

    def test_envfix_sandbox_mixed_add_guard_and_explicit_selection(self):
        state = self.envfix_fixture(agents=[])
        rows = [self.envfix_agent(state, 'one'), self.envfix_agent(state, 'two')]
        (state / 'agents.json').write_text(json.dumps({'agents': rows}))
        (state / 'config/openclaw.json').write_text(json.dumps({'agents': {'list': [
            {'id': 'one', 'sandbox': {'mode': 'off'}},
            {'id': 'two', 'sandbox': {'mode': 'all', 'backend': 'docker', 'docker': {'image': 'keep'}}}]}}))
        before = (state / 'agents.json').read_bytes()
        result = self.envfix_run(state, 'ensure_agent new main token 123')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('explicit sandbox policy', result.stderr)
        self.assertEqual((state / 'agents.json').read_bytes(), before)
        self.assertFalse((state / 'home').exists())
        result = self.envfix_run(state, 'ensure_agent new main "" ""',
                                 extra_env={'OPENCLAW_AGENT_SANDBOX': '{"mode":"off"}'})
        self.assertEqual(result.returncode, 0, result.stderr)
        added = next(a for a in json.loads((state / 'agents.json').read_text())['agents'] if a['id'] == 'new')
        self.assertEqual(added['sandbox'], {'mode': 'off'})

    def test_envfix_sandbox_refresh_never_recreates(self):
        state = self.envfix_fixture()
        result = self.envfix_run(state, r'''
ensure_app_user() { :; }
ensure_group() { :; }
seed_provider_auth() { :; }
write_opencode_config() { :; }
write_helper_scripts() { :; }
restart_openclaw_gateway() { :; }
run_as_app_user_with_env() { echo "unexpected recreate $*" >&2; exit 93; }
cmd_refresh_config
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_envfix_workspace_selected_default_and_empty_duplicate_guard(self):
        state = self.envfix_fixture(agents=[])
        rows = [self.envfix_agent(state, 'first', sandbox={'mode': 'off'}),
                self.envfix_agent(state, 'selected', sandbox={'mode': 'off'}, default=True)]
        rows[1]['workspace'] = str(state / 'custom-selected')
        (state / 'agents.json').write_text(json.dumps({'agents': rows}))
        result = self.envfix_run(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['agents']['defaults']['workspace'], rows[1]['workspace'])
        duplicate = state / 'home/workspace-selected'
        duplicate.mkdir()
        result = self.envfix_run(state)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(duplicate.is_dir())
        self.assertEqual(list(duplicate.iterdir()), [])

    def test_envfix_sandbox_add_inherits_uniform_legacy_or_empty_box_defaults(self):
        legacy = {'mode': 'all', 'backend': 'ssh', 'ssh': {'target': 'user@127.0.0.1:2299'},
                  'containers': {'preserve': ['session-a']}}
        for populated in (True, False):
            with self.subTest(populated=populated):
                state = self.envfix_fixture(agents=[])
                rows = [self.envfix_agent(state, 'old')] if populated else []
                (state / 'agents.json').write_text(json.dumps({'agents': rows}))
                (state / 'config/openclaw.json').write_text(json.dumps({'agents': {
                    'defaults': {'sandbox': legacy}, 'entries': [{'id': 'old'}] if populated else []}}))
                result = self.envfix_run(state, 'ensure_agent new main "" ""')
                self.assertEqual(result.returncode, 0, result.stderr)
                added = next(a for a in json.loads((state / 'agents.json').read_text())['agents'] if a['id'] == 'new')
                self.assertEqual(added['sandbox'], legacy)
                if populated:
                    self.assertNotIn('sandbox', next(a for a in json.loads((state / 'agents.json').read_text())['agents'] if a['id'] == 'old'))

    def test_envfix_sandbox_add_command_explicit_and_malformed_selection(self):
        for policy in ('{"mode":"off"}', '{"mode":"unknown"}'):
            with self.subTest(policy=policy):
                state = self.envfix_fixture()
                before = (state / 'agents.json').read_bytes()
                body = r'''
seed_provider_auth() { :; }
write_opencode_config() { :; }
write_helper_scripts() { :; }
restart_openclaw_gateway() { :; }
cmd_add_agent new --group main --sandbox "$TEST_POLICY"
'''
                result = self.envfix_run(state, body, extra_env={'TEST_POLICY': policy,
                    'OPENCLAW_AGENT_TELEGRAM_BOT_TOKEN': 'fake-token', 'OPENCLAW_AGENT_TELEGRAM_ALLOW_FROM': '123'})
                if 'unknown' in policy:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('sandbox', result.stderr)
                    self.assertEqual((state / 'agents.json').read_bytes(), before)
                    self.assertFalse((state / 'home').exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(self.envfix_config(state)['agents']['list'][1]['sandbox'], {'mode': 'off'})

    def test_envfix_sandbox_generated_audit_off_uses_host_and_reports_missing(self):
        state = self.envfix_fixture()
        source = (SCRIPTS / 'openclaw-vps.sh').read_text()
        # Relocate only generated helper destinations in this disposable fixture.
        source = source.rsplit('\nmain "$@"', 1)[0].replace('/usr/local/sbin/', str(state / 'helpers') + '/')
        helper_source = state / 'source.sh'
        helper_source.write_text(source)
        result = self.envfix_run(state, 'regenerate_openclaw_config\n' +
                                 'mkdir -p "$STATE_DIR/helpers"\n' +
                                 'eval "$(sed -n \'/^write_sandbox_dependency_audit()/,/^write_host_action_helper()/p\' ' +
                                 str(helper_source) + ' | sed \'$d\')"\nwrite_sandbox_dependency_audit')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('rm -rf /tmp/openclaw-vps-venv-check',
                         (state / 'helpers/openclaw-vps-sandbox-audit').read_text())
        self.stub(self.bin / 'sudo', r'''
printf '%s\n' "$*" >> "$CALLS"
case "$*" in
  *ssh*) echo 'unexpected SSH' >&2; exit 94 ;;
  *'openclaw skills'*) printf '{"skills":[]}\n' ;;
  *'command -v git'*|*'command -v gh'*) exit 1 ;;
  *'node -p'*) printf '24\n' ;;
  *'npm --version'*|*'python3 -c'*|*'python3 -m pip'*|*'python3 -m venv'*|*'uv --version'*) ;;
  *) echo "unexpected sudo $*" >&2; exit 95 ;;
esac
''')
        audit = subprocess.run(shell_command(str(state / 'helpers/openclaw-vps-sandbox-audit')),
                               env=self.env, text=True, capture_output=True)
        self.assertNotEqual(audit.returncode, 0)
        self.assertIn('sandbox=off', audit.stdout)
        self.assertIn('backend=host', audit.stdout)
        self.assertIn('exec=gateway', audit.stdout)
        self.assertIn(str(state / 'home/workspace-dorian'), audit.stdout)
        self.assertIn('MISSING bin git', audit.stdout)
        self.assertIn('MISSING bin gh', audit.stdout)
        self.assertNotIn('ssh', self.calls.read_text())

    def test_envfix_named_dorian_setup_transport_and_handoff(self):
        self.setup('OpenClaw', bot='', allow='', initial_id='dorian', initial_label="Dorian's lab")
        env = (self.project / '.env').read_text()
        self.assertIn("OPENCLAW_INITIAL_AGENT_ID=dorian", env)
        self.assertIn("OPENCLAW_INITIAL_AGENT_LABEL=Dorian\\'s\\ lab", env)
        credentials = (self.project / 'credentials.txt').read_text()
        self.assertIn('./agent-box-manage.sh register --runtime openclaw --agent dorian --group main', credentials)

        self.stub_scp_and_capture_ssh()
        result = self.run_hetzner_functions(
            'write_remote_env_file',
            extra_env={'OPENCLAW_INITIAL_AGENT_ID': 'dorian',
                       'OPENCLAW_INITIAL_AGENT_LABEL': "Dorian's lab"},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stdin = self.calls.with_name(self.calls.name + '.stdin').read_text()
        self.assertIn('OPENCLAW_INITIAL_AGENT_ID=dorian\n', stdin)
        self.assertIn("OPENCLAW_INITIAL_AGENT_LABEL=Dorian\\'s\\ lab\n", stdin)

    def test_envfix_named_dorian_vps_json_config_and_host_grant(self):
        state = self.base / 'named-agent-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR" "$OPENCLAW_CONFIG_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[]}\n' > "$AGENTS_FILE"
APP_HOME="$STATE_DIR/home"
BACKUP_DIR="$STATE_DIR/backups"
OPENCLAW_WORKSPACE="$APP_HOME/workspace"
SANDBOX_SSH_KEY="$APP_HOME/.ssh/openclaw-sandbox_ed25519"
SANDBOX_KNOWN_HOSTS_DIR="$APP_HOME/.ssh/openclaw-sandbox-known-hosts"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
chmod() { :; }
sync_agent_workspace_skills() { :; }
ensure_agent dorian main "" "" "$OPENCLAW_INITIAL_AGENT_LABEL" true
regenerate_openclaw_config
write_exec_approvals
''', state=state, extra_env={'OPENCLAW_INITIAL_AGENT_ID': 'dorian',
                             'OPENCLAW_INITIAL_AGENT_LABEL': 'Dorian'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        inventory = json.loads((state / 'agents.json').read_text())
        self.assertEqual(inventory['agents'], [{
            'id': 'dorian', 'group': 'main', 'workspace': str(state / 'home/workspace-dorian'),
            'agentDir': str(state / 'home/.openclaw/agents/dorian/agent'), 'default': True, 'label': 'Dorian',
            'telegramAccount': 'dorian', 'telegramTokenEnv': '',
            'telegramAllowFrom': '', 'ownerAllowFrom': '', 'sandbox': {'mode': 'off'},
        }])
        config_agent = json.loads((state / 'config' / 'openclaw.json').read_text())['agents']['list'][0]
        self.assertEqual(config_agent['id'], 'dorian')
        self.assertTrue(config_agent['default'])
        self.assertEqual(config_agent['identity']['name'], 'Dorian')
        self.assertEqual(config_agent['workspace'], str(state / 'home/workspace-dorian'))
        self.assertEqual(config_agent['agentDir'], str(state / 'home/.openclaw/agents/dorian/agent'))
        approvals = json.loads((state / 'exec-approvals.pending.json').read_text())
        self.assertEqual(list(approvals['agents']), ['dorian'])
        self.assertNotIn('main', approvals['agents'])

    def test_envfix_named_invalid_id_rejected_before_create(self):
        self.env.update(OPENCLAW_INITIAL_AGENT_ID='bad_id',
                        HETZNER_API_TOKEN='test-token-1234567890ab',
                        HETZNER_SERVER_TYPE='cx23', HETZNER_LOCATION='fsn1',
                        SSH_PUBLIC_KEY_PATH=str(self.key) + '.pub',
                        MODEL_API_KEY='test-model-key-1234567890')
        result = self.run_script('openclaw-hetzner.sh', 'preflight', ok=False)
        self.assertIn('invalid OpenClaw initial agent ID', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_envfix_named_missing_id_rejected_before_create(self):
        self.env.update(HETZNER_API_TOKEN='test-token-1234567890ab',
                        HETZNER_SERVER_TYPE='cx23', HETZNER_LOCATION='fsn1',
                        SSH_PUBLIC_KEY_PATH=str(self.key) + '.pub',
                        MODEL_API_KEY='test-model-key-1234567890')
        result = self.run_script('openclaw-hetzner.sh', 'preflight', ok=False)
        self.assertIn('OPENCLAW_INITIAL_AGENT_ID is required', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_envfix_named_label_quoting_round_trips(self):
        self.setup('OpenClaw', bot='', allow='', initial_id='dorian', initial_label="Dorian's $lab")
        env_script = 'source "$1"; printf "%s\\n%s\\n" "$OPENCLAW_INITIAL_AGENT_ID" "$OPENCLAW_INITIAL_AGENT_LABEL"'
        result = subprocess.run(shell_command('-c', env_script, 'bash', str(self.project / '.env')),
                                text=True, capture_output=True, env=self.env, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['dorian', "Dorian's $lab"])

    def test_envfix_named_explicit_main_remains_valid(self):
        self.register('openclaw', agent='main', group='main')
        self.assertEqual(self.state()['boxes'][0]['agents'], [{'id': 'main', 'group': 'main'}])

    def test_envfix_named_register_prompts_for_actual_agent(self):
        result = self.run_script(
            'agent-box-manage.sh', 'register', '--runtime', 'openclaw', '--box', 'test-box',
            '--server-id', '123', '--server-type', 'cx23', '--location', 'fsn1',
            '--public-ip', '192.0.2.1', '--tailscale-ip', '100.64.0.10',
            '--ssh-key', str(self.key), input='dorian\n')
        self.assertIn('agent dorian', result.stdout)
        state = self.state()['boxes'][0]
        self.assertEqual(state['groups'], ['main'])
        self.assertEqual(state['agents'], [{'id': 'dorian', 'group': 'main'}])

    def test_envfix_named_existing_state_install_refuses_without_mutation(self):
        state = self.base / 'existing-managed-state'
        result = self.run_vps_functions(r'''
mkdir -p "$STATE_DIR"
printf '{"groups":[{"id":"main","sshPort":2222}]}\n' > "$GROUPS_FILE"
printf '{"agents":[{"id":"dorian"}]}\n' > "$AGENTS_FILE"
preflight() { :; }
apt_install_hardening_first() { :; }
configure_ssh_hardening() { :; }
configure_fail2ban() { :; }
configure_unattended_upgrades() { :; }
configure_host_timezone() { :; }
prompt_secret() { [[ "$1" == "MODEL_API_KEY" ]] && printf 'test-model-key'; }
ensure_app_user() { :; }
install_tailscale() { :; }
tailscale_up() { :; }
install_node() { :; }
install_incus() { :; }
install_openclaw_and_opencode() { :; }
write_user_env() { :; }
ensure_user_shell_sources_env() { :; }
ensure_group() { :; }
agent_exists() { return 1; }
ensure_agent() { :; }
regenerate_openclaw_config() { :; }
seed_provider_auth() { :; }
write_opencode_config() { :; }
write_exec_approvals() { :; }
install_user_systemd_service() { :; }
write_helper_scripts() { :; }
write_systemd_timers() { :; }
install_all
''', state=state, extra_env={'OPENCLAW_INITIAL_AGENT_ID': 'dorian'})
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('existing managed OpenClaw state', result.stderr)
        self.assertEqual((state / 'groups.json').read_text(), '{"groups":[{"id":"main","sshPort":2222}]}\n')
        self.assertEqual((state / 'agents.json').read_text(), '{"agents":[{"id":"dorian"}]}\n')
        self.assertFalse(self.calls.exists())


    def stub_tracked_git(self, name):
        self.stub(self.bin / 'git', r'''
[[ "$1" == -C ]] || exit 96
project="$2"; shift 2
case "$*" in
  'rev-parse --show-toplevel') printf '%s\n' "$project" ;;
  'ls-files --error-unmatch -- TRACKED') exit 0 ;;
  'ls-files --error-unmatch -- '* ) exit 1 ;;
  *) echo "unexpected git $*" >&2; exit 96 ;;
esac
'''.replace('TRACKED', name))

    def stub_envfix_openclaw(self, schema='mode'):
        self.calls.touch(exist_ok=True)
        # Minimal local JSON-schema fixtures mirror installed config schema output.
        props = {'host': {'enum': ['gateway']}, 'strictInlineEval': {'type': 'boolean'}}
        if schema in ('mode', 'both', 'large'):
            props['mode'] = {'enum': ['deny', 'allowlist', 'ask', 'auto', 'full']}
        if schema in ('legacy', 'both'):
            props.update(security={'enum': ['deny', 'allowlist', 'full']},
                         ask={'enum': ['off', 'on-miss', 'always']})
        schema_file = self.base / 'exec-schema.json'
        schema_file.write_text(json.dumps({'properties': {'tools': {'properties': {
            'exec': {'type': 'object', 'properties': props}}}}}))
        if schema == 'large':
            doc = json.loads(schema_file.read_text())
            doc['description'] = 'x' * 1100000
            schema_file.write_text(json.dumps(doc))
        self.env['EXEC_SCHEMA_FILE'] = str(schema_file)
        self.stub(self.bin / 'sudo', r'''
[[ "$1" == -Hiu && "$2" == openclaw && "$3" == bash && "$4" == -lc && "$#" == 5 ]] || exit 97
printf 'sudo account=%s\n' "$2" >> "$CALLS"
exec bash -c "$5"
''')
        cli = self.bin / 'openclaw'
        cli.write_text('#!' + sys.executable + '\n' + r'''
import json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ.get('OPENCLAW_STATE_DIR', str(pathlib.Path(os.environ['CALLS']).parent / 'approval-state/config')))
state.mkdir(parents=True, exist_ok=True)
store = state / 'active-approvals.json'  # models the active SQLite store, not legacy JSON
with open(os.environ['CALLS'], 'a') as log:
    log.write('openclaw ' + ' '.join(args) + '\n')
    log.write('context ' + str(state) + ' HOME=' + os.environ['HOME'] + ' PATH=' + os.environ['PATH'] + '\n')
if args == ['config', 'schema', '--json']:
    print(pathlib.Path(os.environ['EXEC_SCHEMA_FILE']).read_text())
elif args == ['config', 'validate', '--json']:
    candidate = pathlib.Path(os.environ['OPENCLAW_CONFIG_PATH'])
    assert candidate.name.startswith('openclaw-refresh.'), candidate
    cfg = json.loads(candidate.read_text())
    e = cfg['tools']['exec']
    assert not ('mode' in e and ('security' in e or 'ask' in e))
    sys.exit(int(os.environ.get('VALIDATE_EXIT', 0)))
elif args == ['approvals', 'get', '--json']:
    sys.exit(23) if os.environ.get('GET_EXIT') else None
    print(json.dumps({'exists': store.exists(), 'file': json.loads(store.read_text()) if store.exists() else {'version': 1}}))
elif args[:3] == ['approvals', 'set', '--file'] and len(args) == 4:
    if os.environ.get('OPENCLAW_APPROVALS_EXIT', '0') != '0': sys.exit(24)
    assert not store.exists(), 'fresh defaults must never replace an existing store'
    store.write_text(pathlib.Path(args[3]).read_text())
elif args[:5] == ['approvals', 'allowlist', 'add', '--agent', '*'] and len(args) == 6:
    if os.environ.get('ADD_EXIT', '0') != '0': sys.exit(25)
    doc = json.loads(store.read_text()) if store.exists() else {'version': 1}
    entries = doc.setdefault('agents', {}).setdefault('*', {}).setdefault('allowlist', [])
    if not any(e['pattern'] == args[5] for e in entries): entries.append({'pattern': args[5]})
    store.write_text(json.dumps(doc))
else:
    raise SystemExit('unexpected OpenClaw invocation: ' + repr(args))
''')
        cli.chmod(0o755)

    def approvals_run(self, state, body='seed_exec_allowlist fresh', extra_env=None):
        self.stub_envfix_openclaw()
        return self.run_vps_functions(r'''
APP_HOME="$STATE_DIR/home"
mkdir -p "$STATE_DIR" "$USER_CONFIG_DIR"
printf 'OPENCLAW_STATE_DIR=%q\n' "$STATE_DIR/active state" > "$USER_ENV_FILE"
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
resolve_verified_host_tool() { printf '/usr/bin/%s\n' "$1"; }
''' + body, state=state, extra_env=dict(ENVFIX_REAL_EXEC='1', OPENCLAW_INITIAL_AGENT_ID='dorian', **(extra_env or {})))

    def test_envfix_approvals_wildcard_tools_named_wrapper_active_state(self):
        state = self.base / 'seed'
        result = self.approvals_run(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        doc = json.loads((state / 'active state/active-approvals.json').read_text())
        self.assertEqual([e['pattern'] for e in doc['agents']['*']['allowlist']], ['/usr/bin/git', '/usr/bin/gh'])
        wrapper = doc['agents']['dorian']['allowlist'][0]
        self.assertEqual(wrapper['pattern'], '/usr/local/sbin/openclaw-vps-host-action')
        self.assertEqual(wrapper['argPattern'], '^(install-skill [a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)?|update-skills|refresh-config|sandbox-audit|doctor|restart-vps|as-openclaw .+|as-root .+|write-file-base64 [^|]+)$')
        self.assertNotIn('mode', doc['defaults'])
        self.assertEqual(doc['defaults']['security'], 'allowlist')
        calls = self.calls.read_text()
        self.assertIn('sudo account=openclaw', calls)
        self.assertIn('HOME=' + str(state / 'home'), calls)
        self.assertIn('PATH=' + str(self.bin) + ':/usr/local/bin:/usr/bin:/bin', calls)
        self.assertFalse((state / 'config/exec-approvals.json').exists())
        self.assertFalse((state / 'exec-approvals.pending.json').exists())

    def test_envfix_approvals_existing_restrictive_store_duplicate_additions(self):
        state = self.base / 'seed'
        active = state / 'active state/active-approvals.json'
        active.parent.mkdir(parents=True)
        doc = {'version': 1, 'socket': {'token': 'keep'}, 'defaults': {'security': 'deny', 'ask': 'always'},
               'agents': {'dorian': {'security': 'deny', 'allowlist': [{'pattern': '/operator/tool', 'argPattern': '^safe$'}]},
                          '*': {'ask': 'always', 'allowlist': [{'pattern': '/usr/bin/git', 'id': 'keep'}]}}}
        active.write_text(json.dumps(doc))
        result = self.approvals_run(state, 'seed_exec_allowlist\nseed_exec_allowlist')
        self.assertEqual(result.returncode, 0, result.stderr)
        after = json.loads(active.read_text())
        self.assertEqual(after['defaults'], doc['defaults'])
        self.assertEqual(after['socket'], doc['socket'])
        self.assertEqual(after['agents']['dorian'], doc['agents']['dorian'])
        self.assertEqual(after['agents']['*']['ask'], 'always')
        self.assertEqual(after['agents']['*']['allowlist'], [{'pattern': '/usr/bin/git', 'id': 'keep'}, {'pattern': '/usr/bin/gh'}])
        self.assertNotIn('approvals set', self.calls.read_text())

    def test_envfix_approvals_existing_empty_store_never_imported(self):
        state = self.base / 'seed'
        active = state / 'active state/active-approvals.json'
        active.parent.mkdir(parents=True)
        active.write_text('{"version":1,"agents":{}}')
        result = self.approvals_run(state)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('approvals set', self.calls.read_text())
        self.assertNotIn('dorian', json.loads(active.read_text())['agents'])

    def test_envfix_approvals_get_failure_no_mutation(self):
        state = self.base / 'seed'
        result = self.approvals_run(state, extra_env={'GET_EXIT': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('approvals set', self.calls.read_text())
        self.assertNotIn('allowlist add', self.calls.read_text())

    def test_envfix_approvals_add_failure_prevents_start_retains_pending(self):
        result = self.run_install_with_approval_import(0, add_exit=1)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        pending = self.base / 'approval-state/exec-approvals.pending.json'
        self.assertEqual(pending.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('service', self.calls.read_text().splitlines())
        self.assertFalse((pending.parent / 'config/exec-approvals.json').exists())

    def test_envfix_tools_failure_precedes_any_approval_or_start(self):
        result = self.run_install_with_approval_import(0, tools_exit=1)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('approvals', self.calls.read_text())
        self.assertNotIn('service', self.calls.read_text())

    def test_envfix_approvals_refresh_leaves_removed_grants_removed(self):
        state = self.envfix_fixture()
        store = state / 'config/active-approvals.json'
        store.write_text('{"version":1,"agents":{"*":{"allowlist":[]}}}')
        before = store.read_bytes()
        result = self.envfix_run(state, r'''
ensure_app_user() { :; }; ensure_group() { :; }; seed_provider_auth() { :; }
write_opencode_config() { :; }; write_helper_scripts() { :; }; restart_openclaw_gateway() { :; }
seed_exec_allowlist() { echo unexpected-seed >&2; exit 95; }
cmd_refresh_config
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, store.read_bytes())
        maintenance = (SCRIPTS / 'openclaw-vps.sh').read_text().split('write_maintenance_helper() {', 1)[1].split('\nwrite_helper_scripts()', 1)[0]
        self.assertNotIn('seed_exec_allowlist', maintenance)

    def schema_run(self, schema, config=None, extra_env=None):
        self.stub_envfix_openclaw(schema)
        state = self.envfix_fixture(config=config)
        result = self.run_vps_functions(r'''
APP_HOME="$STATE_DIR/home"
MODEL_CATALOG=testai/model-1
sync_all_agent_workspace_skills() { :; }
install() { while (($#)); do case "$1" in -o|-g|-m) shift 2 ;; -d) shift ;; *) mkdir -p "$1"; shift ;; esac; done; }
chown() { :; }
regenerate_openclaw_config
''', state=state, extra_env=dict(ENVFIX_REAL_EXEC='1', **(extra_env or {})))
        return state, result

    def test_envfix_approvals_schema_normalized_and_legacy_coherent(self):
        for schema in ('mode', 'both', 'legacy'):
            with self.subTest(schema=schema):
                state, result = self.schema_run(schema)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = {'host': 'gateway', 'strictInlineEval': True}
                expected.update({'security': 'allowlist', 'ask': 'off'} if schema == 'legacy' else {'mode': 'allowlist'})
                self.assertEqual(self.envfix_config(state)['tools']['exec'], expected)
                self.assertIn('config validate --json', self.calls.read_text())

    def test_envfix_approvals_schema_preserves_stricter_policy_and_exec_fields(self):
        config = {'tools': {'exec': {'mode': 'deny', 'timeoutSeconds': 99, 'strictInlineEval': True}}}
        state, result = self.schema_run('mode', config)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec'], config['tools']['exec'])

    def test_envfix_approvals_legacy_strict_policy_preserved_or_conversion_refused(self):
        policy = {'security': 'allowlist', 'ask': 'always', 'strictInlineEval': True, 'timeoutSeconds': 71}
        state, result = self.schema_run('legacy', {'tools': {'exec': policy}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec'], policy)
        state, result = self.schema_run('both', {'tools': {'exec': policy}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('without changing policy', result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec'], policy)

    def test_envfix_approvals_existing_legacy_allowlist_normalizes_losslessly(self):
        policy = {'host': 'gateway', 'security': 'allowlist', 'ask': 'off', 'strictInlineEval': True}
        state, result = self.schema_run('both', {'tools': {'exec': policy}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec'],
                         {'host': 'gateway', 'mode': 'allowlist', 'strictInlineEval': True})

    def test_envfix_approvals_mixed_existing_schema_rejected(self):
        policy = {'mode': 'deny', 'security': 'full', 'ask': 'off'}
        state, result = self.schema_run('both', {'tools': {'exec': policy}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ambiguous', result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec'], policy)

    def test_envfix_approvals_schema_unknown_or_validation_failure_preserves_config(self):
        original = {'tools': {'exec': {'mode': 'deny'}}, 'marker': 'usable'}
        for schema, extra in [('unknown', {}), ('mode', {'VALIDATE_EXIT': '1'})]:
            with self.subTest(schema=schema):
                state, result = self.schema_run(schema, original, extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.envfix_config(state), original)
                self.assertNotIn('approvals set', self.calls.read_text())

    def test_envfix_approvals_large_local_schema_is_not_passed_as_one_argument(self):
        state, result = self.schema_run('large')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.envfix_config(state)['tools']['exec']['mode'], 'allowlist')

    def test_envfix_approvals_untrusted_second_tool_prevents_all_grants(self):
        state = self.base / 'seed'
        result = self.approvals_run(state, r'''
resolve_verified_host_tool() {
  if [[ "$1" == git ]]; then printf '/usr/bin/git\n'; else echo 'untrusted gh' >&2; return 1; fi
}
seed_exec_allowlist fresh
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('approvals', self.calls.read_text())

    def test_envfix_tools_rejects_untrusted_resolution_before_executing_it(self):
        self.stub(self.bin / 'gh', 'echo UNTRUSTED_EXECUTED >> "$CALLS"\n')
        result = self.run_vps_functions(r'''
run_as_app_user() {
  case "$1" in
    'command -v git') printf '/bin/bash\n' ;;
    'command -v gh') printf '%s/gh\n' "$USER_BIN_DIR" ;;
    '/bin/bash --version') /bin/bash --version ;;
    *) echo UNEXPECTED_EXECUTION >> "$CALLS"; exit 99 ;;
  esac
}
curl() { echo UNEXPECTED_DOWNLOAD >> "$CALLS"; exit 99; }
ensure_git_gh_installed
''', extra_env={'ENVFIX_REAL_EXEC': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('untrusted executable', result.stderr)
        self.assertFalse(self.calls.exists())

    def tools_fixture(self, arch='x86_64', variant='valid', reuse=False, body='ensure_git_gh_installed'):
        release = self.base / ('release-' + arch + '-' + variant)
        release.mkdir(exist_ok=True)
        cpu = {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(arch, 'amd64')
        name = 'gh_2.78.0_linux_' + cpu
        asset = release / (name + '.tar.gz')
        with tarfile.open(asset, 'w:gz') as tf:
            info = tarfile.TarInfo(name + '/bin/gh')
            payload = ('#!/bin/sh\n[ "$1" = --version ] || exit 98\nprintf "gh version 2.78.0\\n"\n').encode()
            if variant == 'traversal': info.name = '../escaped'
            if variant == 'absolute': info.name = '/tmp/escaped'
            if variant == 'missing': info.name = name + '/README'
            if variant == 'link': info.type = tarfile.SYMTYPE; info.linkname = '/bin/sh'
            info.mode = 0o644 if variant == 'nonexec' else 0o755
            info.size = len(payload) if variant != 'link' else 0
            tf.addfile(info, io.BytesIO(payload))
        digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        if variant == 'checksum': digest = '0' * 64
        manifest = digest + '  ' + asset.name + '\n'
        if variant == 'duplicate-checksum': manifest += manifest
        if variant == 'wrong-release': manifest = manifest.replace('2.78.0', '2.77.0')
        (release / 'gh_2.78.0_checksums.txt').write_text(manifest)
        state = self.base / ('tools-' + arch + '-' + variant)
        state.mkdir(exist_ok=True)
        self.stub(self.bin / 'gh', 'exit 1\n' if variant == 'broken' else
                  '[[ "$*" == --version ]] || exit 99\nprintf "gh version fixture\\n"\n')
        guard = r'''
# File ownership is simulated ONLY at the trust boundary; separate tests exercise it for real.
GH_INSTALL_PATH="$STATE_DIR/installed/gh"
mkdir -p "$STATE_DIR/installed"
run_as_app_user() {
    printf 'service-exec %s\n' "$1" >> "$CALLS"
    case "$1" in
      'command -v git') printf '/usr/bin/true\n' ;;
      'command -v gh') if [[ -f "$GH_INSTALL_PATH" ]]; then printf '%s\n' "$GH_INSTALL_PATH"; elif [[ "$REUSE" == 1 ]]; then printf '%s/gh\n' "$USER_BIN_DIR"; else return 1; fi ;;
      *' --version') bash -c "$1" ;;
      *) echo "unexpected service call $1" >&2; exit 95 ;;
    esac
}
verify_system_executable() { printf 'trust %s\n' "$1" >> "$CALLS"; [[ -x "$1" ]]; }
uname() { [[ "$*" == -m ]] || exit 95; printf '%s\n' "$FIXTURE_ARCH"; }
curl() {
    printf 'fixture-curl %s\n' "$*" >> "$CALLS"
    [[ "$*" == '--fail --silent --show-error --location --proto =https --proto-redir =https --tlsv1.2 --output '* ]] || exit 95
    [[ "$DOWNLOAD_FAIL" != 1 ]] || return 22
    local output="${11}" url="${12}" name
    name="${url##*/}"
    [[ "$DOWNLOAD_FAIL" != manifest || "$name" != *checksums.txt ]] || return 22
    [[ "$url" == "https://github.com/cli/cli/releases/download/v2.78.0/$name" ]] || exit 95
    [[ -f "$RELEASE_FIXTURE/$name" ]] || exit 95
    cp "$RELEASE_FIXTURE/$name" "$output"
}
install() {
    printf 'install %s\n' "$*" >> "$CALLS"
    [[ "$1" == -o && "$2" == root && "$3" == -g && "$4" == root && "$5" == -m && "$6" == 0755 && "$8" == "$GH_INSTALL_PATH" ]] || exit 95
    [[ "$INSTALL_MISSING" != 1 ]] || return 0
    cp "$7" "$8"; /bin/chmod 755 "$8"
}
apt-get() { echo unexpected-package >&2; exit 95; }
runuser() { echo unexpected-runuser >&2; exit 95; }
systemctl() { echo unexpected-systemctl >&2; exit 95; }
sudo() { echo unexpected-sudo >&2; exit 95; }
'''
        result = self.run_vps_functions(guard + body, state=state, extra_env={
            'ENVFIX_REAL_EXEC': '1', 'REUSE': '1' if reuse else '0', 'FIXTURE_ARCH': arch,
            'RELEASE_FIXTURE': str(release), 'DOWNLOAD_FAIL': ('1' if variant == 'download' else 'manifest' if variant == 'manifest-download' else '0'),
            'INSTALL_MISSING': '1' if variant == 'install-missing' else '0'})
        calls = self.calls.read_text() if self.calls.exists() else ''
        self.assertNotIn('auth', calls)
        self.assertNotIn('approvals', calls)
        self.assertNotIn('unexpected', result.stderr)
        return state, result, calls

    def test_envfix_tools_reuse_functioning_installed_binary(self):
        state, result, calls = self.tools_fixture(reuse=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('fixture-curl', calls)
        self.assertNotIn('install ', calls)
        self.assertIn('trust ', calls)

    def test_envfix_tools_replaces_trusted_but_broken_gh(self):
        state, result, calls = self.tools_fixture(reuse=True, variant='broken')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((state / 'installed/gh').is_file())
        self.assertEqual(calls.count('fixture-curl '), 2)

    def test_envfix_tools_missing_git_package_install_and_recheck(self):
        _, result, calls = self.tools_fixture(body=r'''
eval "$(declare -f run_as_app_user | sed '1s/run_as_app_user/fixture_service/')"
run_as_app_user() {
  if [[ "$1" == 'command -v git' && ! -f "$STATE_DIR/git-ready" ]]; then return 1; fi
  fixture_service "$1"
}
apt-get() {
  [[ "$*" == 'install -y git' ]] || exit 95
  printf 'fixture-package git\n' >> "$CALLS"
  touch "$STATE_DIR/git-ready"
}
ensure_git_gh_installed
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('fixture-package git', calls)
        self.assertLess(calls.index('fixture-package git'), calls.index('fixture-curl'))

    def test_envfix_tools_verified_amd64_and_arm64_release(self):
        for arch in ('x86_64', 'aarch64'):
            self.calls.unlink(missing_ok=True)
            state, result, calls = self.tools_fixture(arch)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((state / 'installed/gh').is_file())
            self.assertEqual(calls.count('fixture-curl '), 2)
            self.assertLess(calls.index('checksums.txt'), calls.index('install -o'))

    def test_envfix_tools_checksum_archive_download_and_missing_fail_closed(self):
        for variant in ('checksum', 'duplicate-checksum', 'wrong-release', 'traversal', 'absolute', 'link',
                        'missing', 'nonexec', 'download', 'manifest-download', 'install-missing'):
            self.calls.unlink(missing_ok=True)
            with self.subTest(variant=variant):
                state, result, calls = self.tools_fixture(variant=variant)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((state / 'installed/gh').exists())
                if variant != 'install-missing': self.assertNotIn('install -o', calls)
                if variant not in ('download', 'manifest-download', 'install-missing'):
                    self.assertIn('GitHub CLI verification failed', result.stderr)

    def test_envfix_tools_unsupported_architecture_no_download(self):
        _, result, calls = self.tools_fixture(arch='riscv64')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unsupported', result.stderr)
        self.assertNotIn('fixture-curl', calls)

    def test_envfix_tools_real_trust_rejects_user_owned_and_writable_resolution(self):
        self.stub(self.bin / 'unsafe-tool', 'exit 0\n')
        for target in (str(self.bin / 'unsafe-tool'), 'git', '/does/not/exist'):
            result = self.run_vps_functions('verify_system_executable ' + repr(target), extra_env={'ENVFIX_REAL_EXEC': '1'})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('untrusted executable', result.stderr)
        result = self.run_vps_functions('verify_system_executable /bin/bash', extra_env={'ENVFIX_REAL_EXEC': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_envfix_layout_uses_distribution_relative_to_tests(self):
        self.assertTrue(SCRIPTS.is_dir(), f'missing scripts distribution: {SCRIPTS}')
        self.assertTrue((SCRIPTS / 'setup-agent-box.sh').is_file())

    def test_envfix_layout_discovers_nested_bundle_distribution(self):
        with tempfile.TemporaryDirectory(prefix='envfix-layout-') as directory:
            fixture = Path(directory)
            test_file = fixture / 'tests/test_agent_box.py'
            nested = fixture / '.agents/skills/hetzner-agent-box/scripts'
            test_file.parent.mkdir()
            nested.mkdir(parents=True)
            (nested / 'setup-agent-box.sh').write_text('#!/bin/bash\\n')
            self.assertEqual(_resolve_scripts_dir(test_file), nested)

    def test_envfix_layout_rejects_missing_distribution_clearly(self):
        with tempfile.TemporaryDirectory(prefix='envfix-layout-missing-') as directory:
            test_file = Path(directory) / 'tests/test_agent_box.py'
            test_file.parent.mkdir()
            with self.assertRaisesRegex(RuntimeError, 'could not find scripts distribution'):
                _resolve_scripts_dir(test_file)

    def test_envfix_layout_can_execute_selected_test_bash(self):
        requested = self.bin / 'requested-bash'
        self.stub(requested, 'printf "selected-bash\\n" >> "$CALLS"\nexec /bin/bash "$@"\n')
        self.env['BOXSKILL_TEST_BASH'] = str(requested)
        os.environ['BOXSKILL_TEST_BASH'] = str(requested)
        self.addCleanup(os.environ.pop, 'BOXSKILL_TEST_BASH', None)
        self.run_script('setup-agent-box.sh', '--help')
        self.assertIn('selected-bash', self.calls.read_text())

    def test_envfix_parity_rejects_disposable_fixture_mismatch(self):
        with tempfile.TemporaryDirectory(prefix='envfix-parity-') as directory:
            base = Path(directory)
            canonical = base / 'canonical'
            working = base / 'working'
            for canonical_relative, working_relative in _CROSS_REPO_PAIRS:
                canonical_path = canonical / canonical_relative
                working_path = working / working_relative
                canonical_path.parent.mkdir(parents=True, exist_ok=True)
                working_path.parent.mkdir(parents=True, exist_ok=True)
                canonical_path.write_text(f'fixture {canonical_relative}')
                working_path.write_text(f'fixture {canonical_relative}')
            self.assertEqual(_cross_repo_mismatches(canonical, working), [])
            prior_canonical = os.environ.get('BOXSKILL_CANONICAL_ROOT')
            prior_working = os.environ.get('BOXSKILL_WORKING_ROOT')
            os.environ['BOXSKILL_CANONICAL_ROOT'] = str(canonical)
            os.environ['BOXSKILL_WORKING_ROOT'] = str(working)
            try:
                _enforce_cross_repo_parity()
            finally:
                if prior_canonical is None:
                    os.environ.pop('BOXSKILL_CANONICAL_ROOT', None)
                else:
                    os.environ['BOXSKILL_CANONICAL_ROOT'] = prior_canonical
                if prior_working is None:
                    os.environ.pop('BOXSKILL_WORKING_ROOT', None)
                else:
                    os.environ['BOXSKILL_WORKING_ROOT'] = prior_working
            corrupted = working / _CROSS_REPO_PAIRS[0][1]
            corrupted.write_text('corrupted bytes')
            prior_canonical = os.environ.get('BOXSKILL_CANONICAL_ROOT')
            prior_working = os.environ.get('BOXSKILL_WORKING_ROOT')
            os.environ['BOXSKILL_CANONICAL_ROOT'] = str(canonical)
            os.environ['BOXSKILL_WORKING_ROOT'] = str(working)
            try:
                with self.assertRaisesRegex(RuntimeError, 'content mismatch'):
                    _enforce_cross_repo_parity()
            finally:
                if prior_canonical is None:
                    os.environ.pop('BOXSKILL_CANONICAL_ROOT', None)
                else:
                    os.environ['BOXSKILL_CANONICAL_ROOT'] = prior_canonical
                if prior_working is None:
                    os.environ.pop('BOXSKILL_WORKING_ROOT', None)
                else:
                    os.environ['BOXSKILL_WORKING_ROOT'] = prior_working

    def test_envfix_parity_rejects_half_specified_root_pair(self):
        original_canonical = os.environ.get('BOXSKILL_CANONICAL_ROOT')
        original = os.environ.pop('BOXSKILL_WORKING_ROOT', None)
        os.environ['BOXSKILL_CANONICAL_ROOT'] = str(self.base / 'canonical')
        try:
            with self.assertRaisesRegex(RuntimeError, 'must be set together'):
                cross_repo_roots()
        finally:
            if original_canonical is None:
                os.environ.pop('BOXSKILL_CANONICAL_ROOT', None)
            else:
                os.environ['BOXSKILL_CANONICAL_ROOT'] = original_canonical
            if original is not None:
                os.environ['BOXSKILL_WORKING_ROOT'] = original

    def test_bundle_parity_and_password_printed_once(self):
        for name in ('hermes-hetzner.sh','hermes-vps.sh','openclaw-hetzner.sh','openclaw-vps.sh'):
            self.assertEqual((SCRIPTS / name).read_bytes(), (ROOT / name).read_bytes(), name)
        for runtime in ('hermes','openclaw'):
            script = (ROOT / f'{runtime}-hetzner.sh').read_text()
            summary = script.split('print_summary() {', 1)[1].split('\n}', 1)[0]
            env = dict(os.environ, ROOT_PASSWORD='UNIQUE_TEST_PASSWORD')
            result = subprocess.run(shell_command('-c', summary), capture_output=True, text=True, env=env, check=True)
            self.assertEqual(result.stdout.count('UNIQUE_TEST_PASSWORD'), 1)
            self.assertIn('type CREATE to continue', script)
            confirmation = script.split('confirm_paid_server_create() {', 1)[1].split('\n}', 1)[0]
            for reply, expected in [('no\n', 1), ('CREATE\n', 0)]:
                check = subprocess.run(shell_command('-c', 'fail() { exit 1; }; ' + confirmation),
                                       input=reply, text=True, capture_output=True)
                self.assertEqual(check.returncode, expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
