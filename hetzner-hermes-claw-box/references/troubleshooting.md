# Troubleshooting

Rarely needed procedures for the Hetzner Hermes / Claw Box skill. Start with
[known issues](../docs/agents/known-issues-and-improvements.md) for causes seen
in live deployments.

## Unattended install

Only when the user explicitly requires automation. Non-interactive stdin order:
`printf '\nCREATE\n' | ./openclaw-hetzner.sh install` — one empty line for the
optional bot-token prompt, then the literal word `CREATE` for the paid-server
confirmation. Piping `y` silently reports "server creation cancelled". Under
`ssh -tt` a piped stdin that runs out leaves the remote `read` blocked forever,
so every prompt must be fed.

## Hung remote prompts

If a remote prompt still hangs after the wrapper has fed its spare newline
input, prefer reconnecting and rerunning the operation. As a last resort, use
TIOCSTI pty injection from a trusted interactive session to inject the needed
response into the hung session's controlling terminal; confirm the target
session before injecting. This requires root on the machine that owns the
terminal, Linux 6.2 and later disable TIOCSTI by default
(`dev.tty.legacy_tiocsti`), and macOS does not provide it.

## Hermes legacy migration

Older pre-group installs must migrate default first: upload the current
`hermes-vps.sh` to `/root/hermes-vps.sh`, then run default-group
`refresh-config`. The VPS moves legacy `/var/lib/hermes-vps/hermes-home` into
`groups/default/` and recreates `hermes-agent-default`. Do not trigger
migration with add-group.

## Manual setup

If manual setup is necessary, copy the chosen bundled provisioning pair and
`agent-box-manage.sh` to the external working directory, create `.env` using
the fields in `scripts/setup-agent-box.sh` (`write_example`), generate/reuse a
provisioning key, add ignore rules, and set `.env`/`credentials.txt` to mode
600 before writing secrets. Follow the same interactive install and register
steps.
