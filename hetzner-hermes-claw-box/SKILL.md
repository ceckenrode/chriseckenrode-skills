---
name: hetzner-agent-box
description: Use when setting up either Hermes Agent or OpenClaw on Hetzner Cloud, choosing a server type or location, configuring Hetzner/model-provider/Telegram/Tailscale/SSH credentials, managing existing boxes or agents, adding groups or OpenClaw agents, or running status, doctor, logs, backup, maintenance, refresh-config and inventory commands.
allowed-tools: Bash, Read, Write, Edit
---

# Hetzner Agent Box

Standalone Hetzner/VPS provisioning and management for Hermes (Docker groups) and
OpenClaw (Incus groups and agents). Renamed from `setup-hermes-env`. The four root
provisioning filenames and existing remote paths remain stable. This skill does
not install AgentBox core. Fresh OpenClaw agents use host-authoritative workspaces
with sandbox mode off; retained Incus infrastructure remains available for
existing or explicitly selected sandbox policies.

## Choose the flow

For **setup**, the first question is always **“Hermes or OpenClaw?”** Use the
interactive helper to ask it; do not ask for tokens or replacement decisions
first. For **management**, read the selected box's runtime from `boxes.json` and
use the management helper. Ask which box only if there is more than one and the
request does not identify it.

Read the target repository's AGENTS.md and any applicable conventions before git
operations. Never print secret files into chat or commit live configuration.

## First setup

1. Run from the target project (which must already exist):

   ```bash
   /path/to/hetzner-agent-box/scripts/setup-agent-box.sh --project-dir "$PWD"
   ```

   In a working-repo bundle, the entrypoint is
   `.agents/skills/hetzner-agent-box/scripts/setup-agent-box.sh`; in the canonical
   skill checkout, use `scripts/setup-agent-box.sh`. The helper asks runtime first,
   then, for OpenClaw, requires an initial agent ID matching the managed-ID rules
   and accepts an optional label (defaulting to the ID). It confirms existing-file replacements, presents the
   server choices, validates the Hetzner token, and collects runtime credentials.
   It prepares files only; it does not provision a paid box.

2. Explain the server menu when needed:

   | Type | Class |
   | --- | --- |
   | `cx23` — recommended default | 2 vCPU / 4 GB RAM, cheap shared x86 Intel/AMD |
   | `cax11` | 2 vCPU / 4 GB RAM, shared ARM Ampere (NBG1/HEL1 locations); tools/images must support ARM |
   | `cx33` | 4 vCPU / 8 GB RAM, shared x86, more capacity for groups/agents |

   The chosen type/location pair is validated against the Hetzner
   `/server_types` API response before any secret is collected or file written;
   an invalid pair fails with the type's available locations. Users can enter any
   server type, including a dedicated CCX type, and override the location (default
   `fsn1`; examples `nbg1`, `hel1`). The choices become `HETZNER_SERVER_TYPE` and
   `HETZNER_LOCATION` in `.env` and `credentials.txt`. `.env.example` always uses
   safe defaults, never copied local values. Review the installer's paid-server
   summary before typing `CREATE`. The menu follows [Hetzner's current cost-optimized plans](https://www.hetzner.com/cloud/cost-optimized/).
   [CX22 is deprecated](https://docs.hetzner.com/cloud/servers/deprecated-plans/).

3. Required credentials:

   - Shared: Hetzner project Read & Write token, model provider API key, SSH key.
   - Hermes: Telegram bot token and numeric user allowlist. Writes
     `TELEGRAM_ALLOWED_USERS` and compatibility `TELEGRAM_ALLOW_FROM`, plus
     `HERMES_SSH_KEY_PASSPHRASE` and compatibility `OPENCLAW_SSH_KEY_PASSPHRASE`.
   - OpenClaw: Telegram bot and `TELEGRAM_ALLOW_FROM` optional; writes only
     `OPENCLAW_SSH_KEY_PASSPHRASE` for SSH. Without a bot, configure Telegram later.
     With a bot but no allow-from, use Telegram pairing.
   - Both: optional `TAILSCALE_AUTH_KEY`; blank retains browser login.

   Hetzner token: `https://console.hetzner.cloud/` → Project → Security → API Tokens.
   Telegram: create a bot with `@BotFather`, obtain the numeric user ID via
   `@userinfobot`. Let the user enter secrets directly in the terminal.

4. New SSH keys default to `~/.ssh/agentbox_hetzner_ed25519`. If the legacy
   `~/.ssh/openclaw_hetzner_passphrase_ed25519` exists, the default silently reuses
   it. The user can choose another key. Existing keys are never overwritten;
   a missing `.pub` must be recovered with `ssh-keygen -y` before continuing.
   The helper bundles both runtimes and copies the selected pair plus
   `agent-box-manage.sh` to the project; it asks before replacing differing copies.

5. Verify generated `.env` and `credentials.txt` are mode 600 and gitignored;
   `.env.example` and `boxes.example.json` must contain placeholders only. The
   helper adds ignore rules (including backups and state temporary files) to the
   target `.gitignore`. Custom output paths must stay inside that project.
   Existing secret files are backed up privately only after replacement is
   accepted. Declining `.env` replacement still allows refreshing the example.

6. After setup succeeds, load the selected environment and run **one** installer
   in an interactive terminal:

   ```bash
   set -a && source .env && set +a
   ./hermes-hetzner.sh install
   # Or, when OpenClaw was selected:
   # ./openclaw-hetzner.sh install
   ```

   Non-interactive stdin order (only when automation is explicitly required):
   `printf '\nCREATE\n' | ./openclaw-hetzner.sh install` — one empty line for
   the optional bot-token prompt, then the literal word `CREATE` for the
   paid-server confirmation.

   Use the emitted command if a custom env path was selected. Do not pipe `CREATE`,
   use `yes`, or feed typed confirmations automatically. Hermes host commands are
   opt-in: export `HERMES_HOST_COMMANDS=1` only if the trusted Telegram admin should
   run named host commands through `host-shell`.

7. Watch for the Tailscale browser URL. When it appears, pause and give the URL to
   the user to open and approve the VPS, then wait for their confirmation before
   continuing monitoring. A waiting `tailscale up` is not a failure. An optional
   Tailscale auth key can skip this browser handoff. Both stacks end with UFW
   default-deny inbound, tailscale0 allowed; OpenClaw gateway stays loopback-only.

8. After the installer exits successfully and prints the final handoff, capture
   **only non-secret metadata** with:

   ```bash
   ./agent-box-manage.sh register --runtime hermes
   # Or: ./agent-box-manage.sh register --runtime openclaw
   ```

   Fill the prompts from the completed install: server name, ID, type, location,
   public IPv4, Tailscale IPv4, and absolute private-key path. This is the setup's
   post-install state-seeding step; do not skip it or register a failed/partial
   install as successful. `--created-at` accepts the actual creation time in UTC;
   it otherwise uses registration time. Immediately after a fresh install these
   coincide for operational purposes. All metadata can also be passed as flags
   (see `--help`). The helper never parses or saves an installer transcript.

9. A fresh OpenClaw install records the selected ID as the named default agent in
   the `main` group, with workspace `/home/openclaw/workspace-<id>` and matching
   `agentDir`; `main` is the group, not a silently chosen agent. Fresh sandbox
   mode is `off`, so the host and gateway use the same recorded workspace. The
   installer seeds git/gh approvals once through the supported OpenClaw CLI and
   scopes the host-action wrapper to the initial agent. Existing boxes preserve
   their recorded paths, effective sandbox policy, and approvals: refresh does
   not silently rename or merge workspaces, switch sandbox mode, recreate
   sandboxes, or reseed approvals.

10. If setup asked for optional GitHub bootstrap, run this only after install and
    registration succeed:

    ```bash
    ./agent-box-manage.sh github-bootstrap --box NAME
    ```

    It is interactive and opt-in on each run. The first prompt offers to copy an
    existing local GitHub CLI credential (default no); an unavailable or declined
    credential falls back to manual entry. See [GitHub bootstrap](references/github-bootstrap.md).

11. Put the one-time root password only in local `credentials.txt` if saving it.
   Never put passwords, tokens, or the full installer output in `boxes.json`.
   Both installers print the root password once; adding groups/agents does not
   generate another root password. Keep separate credentials handoff files per
   box when provisioning several (use `--credentials-file credentials-work.txt`).
   Run `./agent-box-manage.sh status --box NAME` to check Tailscale reachability.

## Management

From the machine running the setup helper, use the copied `./agent-box-manage.sh`, or use the bundled
script with `--project-dir /path/to/project`. Requires Bash, jq, and OpenSSH.
Management does not load `.env` automatically: SSH can prompt for the key
passphrase, or the user can load the key with `ssh-add`. Runtime wrappers support
exported passphrase variables. The recorded key and Tailscale IP determine access;
there is no public-IP fallback.

```bash
./agent-box-manage.sh boxes
./agent-box-manage.sh status --box personal
./agent-box-manage.sh doctor --box personal
./agent-box-manage.sh logs --box personal
./agent-box-manage.sh backup --box personal
./agent-box-manage.sh maintenance --box personal
./agent-box-manage.sh refresh-config --box personal
./agent-box-manage.sh add-group --box personal --group work
./agent-box-manage.sh lockdown --box personal
# OpenClaw only:
./agent-box-manage.sh add-agent --box personal --agent reviewer --group work
./agent-box-manage.sh list --box personal
```

One recorded box is selected automatically; multiple boxes require `--box`.
`boxes` is local inventory; OpenClaw `list` queries the live VPS.

### Hermes

`status`, `doctor`, `logs`, `backup`, `maintenance`, `refresh-config`, `add-group`
dispatch through `./hermes-hetzner.sh COMMAND --host TS_IP --ssh-key PUBLIC_KEY
--group GROUP`. Lifecycle group defaults to `default`; select another with
`--group work`. Add-group requires an explicit group, and prompts remotely for
its model provider and Telegram credentials. Per-group environment/secret flags remain
available through the original provisioning scripts (the manager accepts no
secret flags). They must reach the remote process; merely exporting a VPS-only
variable locally does not send it over SSH.

Older pre-group installs must migrate default first: upload the current
`hermes-vps.sh` to `/root/hermes-vps.sh`, then run default-group `refresh-config`.
The VPS moves legacy `/var/lib/hermes-vps/hermes-home` into `groups/default/` and
recreates `hermes-agent-default`. Do not trigger migration with add-group.

### OpenClaw management

`add-group` and `add-agent` dispatch through `./openclaw-hetzner.sh` with the saved
host/key and supplied group/agent. Other lifecycle commands, including `list`,
dispatch through interactive SSH to `/root/openclaw-vps.sh COMMAND`. These commands
act on the whole box: the manager rejects `--group` rather than silently ignoring
it. Add-agent requires a **new bot token** remotely, unlike the optional bot in
first setup; an empty allow-from uses pairing. If the group is missing, the VPS
asks whether to create it.

Existing agents retain their recorded workspace and effective sandbox policy. A
new agent on a mixed-policy legacy box requires an explicit sandbox policy; an
unambiguous existing policy may be inherited. Sandbox off is host-authoritative,
not file isolation: the shared service account can access the host workspace and
retains its configured privileged host actions. Incus groups, containers, and
packages remain installed infrastructure even when an agent runs on the host.

GitHub setup is box-wide and takes no token, agent, or group argument. Per-repository
deploy-key registration is a separate future explicit operator action; installation
and bootstrap never perform it. See [workspace recovery](references/workspace-recovery.md)
before reconciling old workspace or policy state.

OpenClaw `agents.json` supports these optional per-agent fields: `subagents` (an
object with `model`, `thinking`, and `delegationMode`), `skills` (an array that is
the agent's final set and takes precedence over the `OPENCLAW_AGENT_SKILLS`
environment setting), `contextInjection`, `bootstrapMaxChars`,
`bootstrapTotalMaxChars`, `tools`, and `heartbeat`. Agent display names in the
generated config come from `identity.name`; `label` remains the input field and
is mapped to `identity.name` in the output.

When `MODEL_CATALOG` is unset, the installer discovers models from the provider's
OpenAI-compatible `/models` endpoint.

`refresh-config` regenerates managed configuration sections while preserving
operator-owned `plugins`, `mcp`, `secrets`, and `tools.web` sections. Dashboard
and plugin changes therefore survive a refresh.

For Telegram pairing, SSH into the box, run `sudo -iu openclaw`, then
`openclaw pairing list telegram` and `openclaw pairing approve telegram CODE`
using the actual code after messaging the bot. Configure a bot first if one was
omitted at setup.

#### Dashboard over Tailscale

OpenClaw's dashboard can stay available from any device in the tailnet, including a
phone with the Tailscale app. The `serve` command persists Tailscale Serve with
`--bg`; the managed `serve.enabled` flag makes the periodic maintenance helper
re-assert that configuration, and systemd lingering keeps the gateway user service
running from boot. Before enabling it once, turn on both **MagicDNS** and **HTTPS
Certificates** in the Tailscale admin console.

```bash
./agent-box-manage.sh serve --box NAME
./agent-box-manage.sh serve-off --box NAME
```

On a phone, open the Tailscale app, then a browser, and visit the printed
`https://<box>.<tailnet>.ts.net` URL to log in to the gateway. Gateway token auth
still applies. This is tailnet-only Tailscale Serve, not Funnel; nothing is exposed
to the public internet. For boxes installed from the GitHub raw URL before this
change, upload the updated script first:
`scp openclaw-vps.sh root@<ts-ip>:/root/openclaw-vps.sh`.

### State and interactive operations

See [boxes.example.json](boxes.example.json) for schema version 1: `boxes` contains
`name`, `runtime`, string `server_id`, `server_type`, `location`, `public_ip`,
`tailscale_ip`, absolute `ssh_key_path`, `groups`, `agents` (`{id, group}`),
`paths` (`vps_script`, `state_dir`), and `created_at` UTC timestamp. Hermes starts
with `groups: ["default"]`, `agents: []`; OpenClaw starts with the selected named
agent in the `main` group. Its remote record includes `default`, `label`,
`workspace`, `agentDir`, and explicit `sandbox` policy. A fresh default workspace
is `/home/openclaw/workspace-<id>`; an existing record's validated `workspace` is
authoritative. Remote paths are `/root/<runtime>-vps.sh` and `/var/lib/<runtime>-vps`.

The state file is local-only, mode 600, schema-validated and written atomically.
Registration appends; duplicate names/server IDs are rejected. Additions update
state only on a successful remote exit, under a local writer lock. The VPS is
still authoritative: after dropped connections, external changes, or registering
an older box, inspect live status/list and reconcile **only the schema's metadata**
in the local JSON; do not copy remote agents.json or secrets wholesale. Maintain
mode 600. Legacy boxes remain unchanged until an operator explicitly migrates
them. No automatic remote inventory import, workspace rename/merge, duplicate
deletion, or sandbox switch is performed.

`lockdown` uses `ssh -tt` to the selected VPS script for both runtimes so the typed
`LOCKDOWN` prompt stays interactive. All remote operations preserve stdin;
confirmations are never answered by the manager. `logs` follows until interrupted.
Do not run destructive operations without the user's authorization or bypass their
confirmation. This helper provides no delete/restart/arbitrary-shell command.

## Verification

Use `python3 -m json.tool boxes.example.json`,
`python3 -B -m unittest discover -s tests -v`, and
`BOXSKILL_TEST_BASH=/bin/bash /bin/bash tests/test_offline_bash.sh`. The shell gate
checks the distributed scripts; tests stub curl/SSH/provisioning and never create
servers. ShellCheck is preferred when installed. These are offline checks only:
live acceptance additionally requires paid-server confirmation, Tailscale approval,
the completed handoff, remote status, and any chosen future GitHub/repository checks.

For explicit recovery, approval re-scoping, or repository deploy-key registration,
follow [workspace recovery](references/workspace-recovery.md) and
[GitHub bootstrap](references/github-bootstrap.md). No recovery or deploy-key
action is automatic.

If a remote prompt still hangs after the wrapper has fed its spare newline input,
use TIOCSTI pty injection from a trusted interactive session to inject the needed
response into the hung session's controlling terminal. Confirm the target session
before injecting; if TIOCSTI is unavailable, reconnect and rerun the operation.

If the OpenClaw backup fails with `Archive symbolic link target must be relative`,
Chrome transient symlinks need cleanup — this is handled automatically by the
generated backup helper (requires the latest version of this script).

If manual setup is necessary, copy the chosen bundled provisioning pair and
`agent-box-manage.sh` to the project, create `.env` from the example, generate/reuse
a provisioning key, add ignore rules, and set `.env`/`credentials.txt` to mode 600
before writing secrets. Follow the same interactive install and register steps.
