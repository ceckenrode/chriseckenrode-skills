# Hetzner Hermes / Claw Box

Set up and manage **Hermes Agent** or **OpenClaw** on a Tailscale-only Ubuntu 24.04
Hetzner VPS. Renamed from `setup-hermes-env`. Existing root script names and remote
paths remain compatible. This is a standalone provisioning POC.

## Prerequisites

Bash, curl, OpenSSH (`ssh`, `ssh-keygen`, `ssh-add`), and jq. Install dependencies
with the package manager on the machine running the setup helper. OpenSSL generates a
new key passphrase when one is not supplied. Have Tailscale connected on that machine.

## Setup

The skill folder is stateless. Choose a separate working directory for credentials,
environment files, box inventory, and prepared runtime scripts. Helpers reject
paths inside skill folders (identified by `SKILL.md`), including nested and
symlinked paths. Run installers from the prepared working directory, not here.
The setup helper generates `.env.example` there from built-in placeholders.
`boxes.example.json` is a static schema template used by the helper, not live state.

From the target project, using the absolute path to this skill:

```bash
/path/to/hetzner-hermes-claw-box/scripts/setup-agent-box.sh --project-dir "$PWD"
```

A copied skill works in any existing target folder. Run
`/path/to/hetzner-hermes-claw-box/scripts/setup-agent-box.sh --help` for output overrides.
Custom env/example/credentials paths must remain inside that folder. For multiple
boxes, use separate env and credentials files (for example `--env-file .env.work
--credentials-file credentials-work.txt`) and a shared `boxes.json` inventory.

The first question is **Hermes or OpenClaw?** The helper then asks for a server
class and location. `cx23` is recommended: 2 vCPU / 4 GB RAM, cheap shared x86.
Other curated choices are `cax11` (2 vCPU / 4 GB, shared ARM, NBG1/HEL1 locations)
and `cx33` (4 vCPU /
8 GB, shared x86). Any type can be entered, including dedicated CCX plans.
Location defaults to `fsn1` and can be overridden. ARM requires compatible tools
and images. These are [current Hetzner plan classes](https://www.hetzner.com/cloud/cost-optimized/),
not a capacity guarantee; [CX22 is deprecated](https://docs.hetzner.com/cloud/servers/deprecated-plans/).

Both runtimes require a Hetzner token and a model provider API key. Hermes also requires a Telegram bot
and numeric user allowlist. OpenClaw accepts empty Telegram fields: configure a
bot later if omitted; a configured bot with no allow-from uses pairing. Numeric
allowlists accept comma- or space-separated IDs.

New keys use `~/.ssh/agentbox_hetzner_ed25519`; the legacy
`~/.ssh/openclaw_hetzner_passphrase_ed25519` is silently reused as the default if
present. You can choose another existing key. The helper writes mode-600 `.env`
and `credentials.txt`, safe examples, and ignore rules, and copies the chosen
runtime's two scripts plus `agent-box-manage.sh`. Replacements require confirmation;
existing credentials get private backups. It does not create a server.

After setup, run the command printed by the helper. With default paths:

```bash
set -a && source .env && set +a
./hermes-hetzner.sh install
# Choose this instead for OpenClaw:
# ./openclaw-hetzner.sh install
```

`HETZNER_SERVER_TYPE`/`HETZNER_LOCATION` come from `.env`. Type **CREATE** at the
paid-server prompt. Do not pipe in confirmations. If Tailscale prints a browser
URL, open it and approve the VPS before continuing; setting optional
`TAILSCALE_AUTH_KEY` beforehand skips that handoff. Hermes named host commands are
opt-in (`HERMES_HOST_COMMANDS=1`) only for a trusted Telegram admin.

Once install succeeds, save the one-time root password only in local
`credentials.txt` if desired, then record the non-secret handoff:

```bash
./agent-box-manage.sh register --runtime hermes
# Or: ./agent-box-manage.sh register --runtime openclaw
./agent-box-manage.sh status
```

Registration prompts for the box name, Hetzner server ID/type/location, public
IPv4, Tailscale IPv4 and absolute private-key path. Use the values from the
successful install; failed installs must not be registered as successful. Every
field can also be supplied as a flag; see `./agent-box-manage.sh --help`.

## Local state

[boxes.example.json](boxes.example.json) is a placeholder-only schema example,
also committed at the repo root. Do not use its addresses as live targets.
`boxes.json` is gitignored, mode 600, with this structure:

```json
{
  "version": 1,
  "boxes": [
    {
      "name": "example-hermes",
      "runtime": "hermes",
      "server_id": "123456",
      "server_type": "cx23",
      "location": "fsn1",
      "public_ip": "192.0.2.1",
      "tailscale_ip": "100.64.0.1",
      "ssh_key_path": "/absolute/path/to/private-key",
      "groups": ["default"],
      "agents": [],
      "paths": {
        "vps_script": "/root/hermes-vps.sh",
        "state_dir": "/var/lib/hermes-vps"
      },
      "created_at": "2000-01-01T00:00:00Z"
    }
  ]
}
```

OpenClaw uses runtime `openclaw`, paths `/root/openclaw-vps.sh` and
`/var/lib/openclaw-vps`, initial groups `["main"]`, and agents
`[{"id":"main","group":"main"}]`. Server IDs are strings. `created_at` defaults
to registration time; pass `--created-at YYYY-MM-DDTHH:MM:SSZ` for the actual
creation time when registering later.

The helper rejects unknown fields, invalid addresses/paths and duplicate box
names/server IDs. It never sources the JSON or copies tokens/passwords into it.
Add-group/add-agent record metadata only after a successful remote exit, with
atomic writes and a writer lock. Remote state remains authoritative. After an
interrupted command or changes outside the helper, inspect live state and reconcile
only these fields locally; keep mode 600. Registering an older box seeds the initial
defaults, so reconcile any additional groups/agents afterward.

## Manage boxes, groups and agents

Run from the project, or add `--project-dir /path/to/project`. One recorded box is
automatically selected; with multiple boxes, use `--box NAME`. `--state FILE`
selects another gitignored JSON inventory inside the project.

```bash
./agent-box-manage.sh boxes
./agent-box-manage.sh status --box example-hermes
./agent-box-manage.sh doctor --box example-hermes --group default
./agent-box-manage.sh logs --box example-hermes --group default
./agent-box-manage.sh backup --box example-hermes
./agent-box-manage.sh maintenance --box example-hermes
./agent-box-manage.sh refresh-config --box example-hermes
./agent-box-manage.sh add-group --box example-hermes --group work
./agent-box-manage.sh lockdown --box example-hermes
# OpenClaw:
./agent-box-manage.sh add-group --box example-openclaw --group work
./agent-box-manage.sh add-agent --box example-openclaw --agent reviewer --group work
./agent-box-manage.sh list --box example-openclaw
./agent-box-manage.sh serve --box example-openclaw
./agent-box-manage.sh serve-off --box example-openclaw
```

| Runtime | Dispatch |
| --- | --- |
| Hermes | Lifecycle and add-group use `./hermes-hetzner.sh COMMAND --host TS_IP --ssh-key PUBLIC_KEY --group GROUP`; default group is `default`. |
| OpenClaw | Add-group/add-agent use `./openclaw-hetzner.sh` with saved host/key and supplied IDs; other lifecycle commands and `list` use `ssh -tt -i PRIVATE_KEY root@TS_IP /root/openclaw-vps.sh COMMAND`. |
| Both | Lockdown runs via interactive SSH to the recorded VPS script; type `LOCKDOWN` yourself. |

OpenClaw lifecycle commands apply to the whole box and reject group selectors.
Hermes add-group prompts for group credentials; OpenClaw add-agent requires a new
Telegram bot token and accepts an empty allow-from for pairing. To approve pairing,
SSH in, run `sudo -iu openclaw`, then `openclaw pairing list telegram` and
`openclaw pairing approve telegram CODE` after messaging the bot.

### OpenClaw dashboard over Tailscale

Finish OpenClaw setup by enabling Serve, checking the actual dashboard URL from
the same tailnet, and giving the user that clickable URL. Tell them to connect to
Tailscale, open the dashboard, and download/install its PWA using their browser's
**Install app** or **Add to Home Screen** option. If installation is unavailable,
use the browser. Do not include gateway tokens in shared links. Report any
unverified access or pending Tailscale approval instead of claiming completion.

Enable **MagicDNS** and **HTTPS Certificates** once in the Tailscale admin console,
then use `./agent-box-manage.sh serve --box NAME`. Tailscale Serve is configured
with `--bg` and persists across reboot; the managed `serve.enabled` flag also makes
the periodic maintenance helper re-assert it, while systemd lingering keeps the
OpenClaw gateway user service running from boot. Disable it with
`./agent-box-manage.sh serve-off --box NAME`.

On a phone, enable the Tailscale app, open a browser, visit the printed
`https://<box>.<tailnet>.ts.net` URL, and use the gateway login. Gateway token auth
still applies. This is not Funnel: it is tailnet-only and nothing is exposed to the
public internet. For boxes installed from the GitHub raw URL before this change,
upload the updated script first with
`scp openclaw-vps.sh root@<ts-ip>:/root/openclaw-vps.sh`.

The manager does not source `.env`; encrypted keys prompt normally or can be
loaded with `ssh-add`. Original wrappers also honor exported runtime-specific
passphrase variables. No confirmation is auto-answered and no public-IP fallback
is used. `logs` follows until interrupted. Adding groups or agents creates no new
root password.

For a pre-group Hermes install, upload the current `hermes-vps.sh` to
`/root/hermes-vps.sh` and run default-group `refresh-config` before adding groups.
It migrates legacy Hermes home into `groups/default/` and recreates
`hermes-agent-default`.

## Verification

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/setup-agent-box.sh
bash -n scripts/agent-box-manage.sh
```

Tests use local stubs for API/SSH/provisioning; they never create a paid server.
Run syntax checks for every edited shell file and ShellCheck when installed.
See [SKILL.md](SKILL.md) for the agent workflow and manual fallback. Never commit
`.env`, `credentials.txt`, `boxes.json`, or their backups. Examples contain only
placeholders. After lockdown both stacks allow inbound via tailscale0 only;
OpenClaw's gateway binds to loopback.
