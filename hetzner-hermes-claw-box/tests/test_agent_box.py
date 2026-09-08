"""Offline contract tests: all API, SSH, key generation and provisioning are stubbed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'scripts'


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
        self.stub(self.bin / 'ssh', 'printf "%s\\n" "$@" > "$CALLS"\nexit "${REMOTE_EXIT:-0}"\n')
        self.stub(self.bin / 'ssh-keygen', 'printf "%s\\n" "$@" > "$CALLS"\n')

    def stub(self, path, body):
        path.write_text('#!/usr/bin/env bash\nset -Eeuo pipefail\n' + body)
        path.chmod(0o755)

    def run_script(self, name, *args, input='', ok=True):
        result = subprocess.run(['bash', str(SCRIPTS / name), *args], cwd=self.project,
                                env=self.env, input=input, text=True, capture_output=True, timeout=15)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def setup(self, runtime='Hermes', bot='test-bot', allow='12345', extra='', env_options=(),
              server_type='', location='', key_path='', ok=True):
        # Fake token is only consumed by the curl executable installed above.
        values = [runtime, server_type, location, '', 'test-token', '', 'testai', 'https://api.testai.example/v1', 'test-model-key-1234567890', 'testai/model-1', bot,
                  allow, '', key_path, 'pass$`word']
        return self.run_script('setup-agent-box.sh', *env_options, input='\n'.join(values) + '\n' + extra, ok=ok)

    def register(self, runtime='hermes', box='test-box', server_id='123', **kwargs):
        return self.run_script('agent-box-manage.sh', 'register', '--runtime', runtime,
                               '--box', box, '--server-id', server_id, '--server-type', 'cx23',
                               '--location', 'fsn1', '--public-ip', '192.0.2.1',
                               '--tailscale-ip', '100.64.0.10', '--ssh-key', str(self.key), **kwargs)

    def state(self):
        return json.loads((self.project / 'boxes.json').read_text())

    def wrapper(self, runtime):
        self.stub(self.project / f'{runtime}-hetzner.sh', 'printf "%s\\n" "$@" > "$CALLS"\nexit "${REMOTE_EXIT:-0}"\n')

    def run_vps_functions(self, command, state=None, gateway=True, tailscale_exit=0,
                          tailscale_error='', extra_env=None):
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
        source = (ROOT / 'openclaw-vps.sh').read_text().rsplit('\nmain "$@"', 1)[0]
        state_dir = Path(state or (self.base / 'openclaw-state'))
        env = dict(self.env, CURL_GATEWAY_OK='1' if gateway else '0',
                   TAILSCALE_EXIT=str(tailscale_exit), TAILSCALE_ERROR=tailscale_error,
                   MODEL_PROVIDER='testai', MODEL_BASE_URL='https://api.testai.example/v1',
                   MODEL_API_KEY='test-model-key', MODEL_ID='testai/model-1')
        if extra_env:
            env.update(extra_env)
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
{command}
'''
        return subprocess.run(['bash', '-c', source + overrides], cwd=self.project,
                              env=env, text=True, capture_output=True, timeout=15)

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
        env = subprocess.check_output(['bash', '-c', script, 'bash', str(self.project / '.env')], text=True)
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
        result = self.run_script('setup-agent-box.sh', input='OpenClaw\n\n\ntest-token\ntestai\nhttps://api.testai.example/v1\nshort\ntest-model-key-1234567890\ntestai/model-1\n\n\n\n\npass\n')
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
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        tracked = self.project / 'tracked.env'
        tracked.write_text('tracked')
        subprocess.run(['git', '-C', str(self.project), 'add', 'tracked.env'], check=True)
        result = self.run_script('setup-agent-box.sh', '--env-file', 'tracked.env',
                                 input='Hermes\n', ok=False)
        self.assertIn('already tracked', result.stderr)
        self.assertEqual(tracked.read_text(), 'tracked')

    def test_manage_refuses_tracked_state_target(self):
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        tracked = self.project / 'tracked-state.json'
        tracked.write_text('{"version":1,"boxes":[]}\n')
        subprocess.run(['git', '-C', str(self.project), 'add', 'tracked-state.json'], check=True)
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
        r = self.run_script('setup-agent-box.sh', input='OpenClaw\n\n\ntest-invalid\n', ok=False)
        self.assertIn('validation failed', r.stderr)
        self.assertFalse((self.project / '.env').exists())

    def test_preserve_existing_secrets(self):
        self.setup()
        before = (self.project / '.env').read_bytes()
        self.run_script('setup-agent-box.sh', input='OpenClaw\n\n\ntest-token\nn\ny\n')
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
            ['bash', '-c', command, str(copy), str(copy)],
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
                ['bash', '-c', 'source "$1"\nROOT_PASSWORD=$2\nparse_args --credentials-file saved.txt\nprint_summary', 'bash', str(partial), f'{runtime}-root-password'],
                cwd=self.project, env=env, text=True, capture_output=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            saved = self.project / 'saved.txt'
            self.assertEqual(saved.read_text(), f'ROOT_PASSWORD={runtime}-root-password\n')
            self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
            self.assertIn('saved root password to saved.txt', result.stdout)
            saved.unlink()

            subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
            tracked = self.project / 'tracked-credentials.txt'
            tracked.write_text('keep me\n')
            subprocess.run(['git', '-C', str(self.project), 'add', tracked.name], check=True)
            result = subprocess.run(
                ['bash', '-c', 'source "$1"\nROOT_PASSWORD=$2\nparse_args --credentials-file tracked-credentials.txt\nprint_summary', 'bash', str(partial), f'{runtime}-root-password'],
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
  {"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""},
  {"id":"reviewer","group":"main","workspace":"/tmp/reviewer","agentDir":"/tmp/reviewer-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
  {"id":"dorian","label":"Dorian","workspace":"/tmp/dorian","agentDir":"/tmp/dorian-agent","group":"main","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""},
  {"id":"boros","label":"Boros","workspace":"/tmp/boros","agentDir":"/tmp/boros-agent","group":"main","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}
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
  '{"id":"reze","group":"main","workspace":"/tmp/reze","agentDir":"/tmp/reze-agent","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","subagents":{"model":"testai/subagent","thinking":"high","delegationMode":"parallel"},"skills":["github","summarize"],"contextInjection":"continuation-skip","bootstrapMaxChars":8000,"bootstrapTotalMaxChars":8000,"tools":{"alsoAllow":["browser","web_fetch"],"sandbox":{"mode":"all"}},"heartbeat":{"every":"0m"}},' \
  '{"id":"dorian","group":"main","workspace":"/tmp/dorian","agentDir":"/tmp/dorian-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}' \
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
            'telegramAllowFrom': '', 'ownerAllowFrom': ''}
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
printf '%s\n' '{"agents":[{"id":"reze","group":"main","workspace":"/tmp/reze","agentDir":"/tmp/reze-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":"","subagents":"wrong"}]}' > "$AGENTS_FILE"
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
printf '%s\n' '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","default":true,"telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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
printf '{"agents":[{"id":"main","group":"main","workspace":"/tmp/main","agentDir":"/tmp/main-agent","telegramTokenEnv":"","telegramAllowFrom":"","ownerAllowFrom":""}]}\n' > "$AGENTS_FILE"
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

    def run_install_with_approval_import(self, exit_code):
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
printf 'openclaw %s\n' "$*" >> "$CALLS"
if [[ "$1" == "approvals" && "${OPENCLAW_APPROVALS_EXIT:-0}" != 0 ]]; then
    exit "$OPENCLAW_APPROVALS_EXIT"
fi
''')
        state = self.base / 'approval-state'
        return self.run_vps_functions(r'''
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
''', state=state, extra_env={'OPENCLAW_APPROVALS_EXIT': str(exit_code)})

    def test_exec_approvals_imports_before_service_without_legacy_file(self):
        result = self.run_install_with_approval_import(0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.base / 'approval-state'
        calls = self.calls.read_text().splitlines()
        self.assertIn(f'openclaw approvals set --file {state}/exec-approvals.pending.json', calls)
        self.assertLess(calls.index(f'openclaw approvals set --file {state}/exec-approvals.pending.json'), calls.index('service'))
        self.assertFalse((state / 'exec-approvals.pending.json').exists())
        self.assertFalse((state / 'config' / 'exec-approvals.json').exists())

    def test_exec_approvals_import_failure_writes_legacy_fallback(self):
        result = self.run_install_with_approval_import(1)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = self.base / 'approval-state'
        legacy = state / 'config' / 'exec-approvals.json'
        pending = state / 'exec-approvals.pending.json'
        self.assertIn('approvals import failed; legacy file left at OPENCLAW_CONFIG_DIR/exec-approvals.json for doctor --fix', result.stderr)
        self.assertTrue(legacy.exists())
        self.assertTrue(pending.exists())
        self.assertEqual(legacy.read_text(), pending.read_text())
        self.assertEqual(legacy.stat().st_mode & 0o777, 0o600)

    def test_preflight_catches_short_provider_key_and_bad_location(self):
        self.env.update(
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
        subprocess.run(['git', 'init', '-q', str(self.project)], check=True)
        self.setup(env_options=('--env-file', '.env.work', '--credentials-file', 'credentials work.txt'))
        self.register()
        ignored = ['.env.work', '.env.work.bak.test', 'credentials work.txt',
                   'credentials work.txt.bak.test', 'boxes.json', 'boxes.json.tmp.test', 'boxes.json.lock']
        for name in ignored:
            result = subprocess.run(['git', 'check-ignore', '-q', name], cwd=self.project)
            self.assertEqual(result.returncode, 0, name)
        for name in ('.env.example', 'boxes.example.json'):
            result = subprocess.run(['git', 'check-ignore', '-q', name], cwd=self.project)
            self.assertEqual(result.returncode, 1, name)

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
        active = subprocess.run(['bash', str(helper)], cwd=self.project, env=self.env,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(active.returncode, 0, active.stdout + active.stderr)
        self.assertIn('tailscale serve --bg http://127.0.0.1:18789', self.calls.read_text())

        self.calls.unlink()
        (state / 'serve.enabled').unlink()
        inactive = subprocess.run(['bash', str(helper)], cwd=self.project, env=self.env,
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

    def test_bundle_parity_and_password_printed_once(self):
        for name in ('hermes-hetzner.sh','hermes-vps.sh','openclaw-hetzner.sh','openclaw-vps.sh'):
            self.assertEqual((SCRIPTS / name).read_bytes(), (ROOT / name).read_bytes(), name)
        for runtime in ('hermes','openclaw'):
            script = (ROOT / f'{runtime}-hetzner.sh').read_text()
            summary = script.split('print_summary() {', 1)[1].split('\n}', 1)[0]
            env = dict(os.environ, ROOT_PASSWORD='UNIQUE_TEST_PASSWORD')
            result = subprocess.run(['bash', '-c', summary], capture_output=True, text=True, env=env, check=True)
            self.assertEqual(result.stdout.count('UNIQUE_TEST_PASSWORD'), 1)
            self.assertIn('type CREATE to continue', script)
            confirmation = script.split('confirm_paid_server_create() {', 1)[1].split('\n}', 1)[0]
            for reply, expected in [('no\n', 1), ('CREATE\n', 0)]:
                check = subprocess.run(['bash', '-c', 'fail() { exit 1; }; ' + confirmation],
                                       input=reply, text=True, capture_output=True)
                self.assertEqual(check.returncode, expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
