# Hetzner Hermes / Claw Box

Set up and manage **Hermes Agent** or **OpenClaw** on a Tailscale-only Ubuntu 24.04 Hetzner VPS.

## Prerequisites

Bash, curl, OpenSSH (`ssh`, `ssh-keygen`, `ssh-add`), and jq on the machine running the
setup helper. OpenSSL generates a new key passphrase when one is not supplied. Have
Tailscale connected on that machine.

## Setup

The skill folder is stateless. Choose a separate working directory for credentials,
environment files, box inventory, and prepared runtime scripts; helpers reject paths
inside skill folders. Run installers from the prepared working directory.

```bash
/path/to/hetzner-hermes-claw-box/scripts/setup-agent-box.sh --project-dir "$PWD"
```

The first question is Hermes or OpenClaw; then server type and location (`cx23`
recommended; any type may be entered; validated against Hetzner before writing anything).

Both runtimes need a Hetzner project token and a model provider API key; Hermes also
needs a Telegram bot token and numeric allowlist; OpenClaw's Telegram fields are
optional. The helper writes mode-600 `.env`/`credentials.txt`, adds ignore rules, and
copies the chosen runtime's scripts plus `agent-box-manage.sh`.

```bash
set -a && source .env && set +a
./hermes-hetzner.sh install
# Choose this instead for OpenClaw:
# ./openclaw-hetzner.sh install
```

Type **CREATE** at the paid-server prompt; do not pipe in confirmations. If
Tailscale prints a browser URL, open it and approve the VPS before continuing.

```bash
./agent-box-manage.sh register --runtime hermes
# Or: ./agent-box-manage.sh register --runtime openclaw
./agent-box-manage.sh status
```

## Local state

`boxes.json` is gitignored, mode 600, metadata only; see
[boxes.example.json](boxes.example.json) for the schema. Remote state is authoritative.

## Manage boxes, groups and agents

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

One recorded box is auto-selected; use `--box NAME` for multiple, `--state FILE` for
another inventory. The manager does not source `.env`; no confirmation is auto-answered.

### OpenClaw dashboard over Tailscale

Enable **MagicDNS** and **HTTPS Certificates** once in the Tailscale admin console,
run `./agent-box-manage.sh serve --box NAME`, and give the user the printed
`https://<box>.<tailnet>.ts.net` URL. This is tailnet-only Tailscale Serve, not Funnel.

## Verification

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/setup-agent-box.sh
bash -n scripts/agent-box-manage.sh
```

Tests use local stubs for API/SSH/provisioning; they never create a paid server.
Never commit `.env`, `credentials.txt`, `boxes.json`, or their backups. See
[SKILL.md](SKILL.md) for the full agent procedure and
[references/troubleshooting.md](references/troubleshooting.md) for the rest.
