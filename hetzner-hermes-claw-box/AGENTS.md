# Hetzner Agent Box Guide

This project is a standalone agent-on-Hetzner POC. It uses an agent-agnostic setup skill
and bundled scripts to provision Tailscale-only Ubuntu VPS boxes on Hetzner Cloud running
either **Hermes Agent** (Docker groups) or **OpenClaw** (Incus groups + agents).

## Working Rules

- Keep this skill folder stateless. Generate runtime configuration and inventory
  only in a separate working directory; the setup helper generates `.env.example`
  there from built-in placeholders.

- The skill and helpers must stay agent-agnostic: first question is always Hermes or
  OpenClaw, then agent-specific setup. Never hardcode one runtime's flow as the only flow.
- Keep this project focused on Hetzner/VPS provisioning and box/agent management for the
  two supported runtimes. Do not mix in AgentBox core installer work.
- Never commit real credentials. `.env`, `credentials.txt`, and box state files with live
  details are local-only and gitignored.
- Keep `.env.example` safe: placeholders only, no live tokens, passwords, API keys, bot
  tokens, or Tailscale auth keys.
- Prefer the setup skill helper for first-time setup; use
  `scripts/setup-agent-box.sh` (renamed from
  `setup-hermes-env`). Use the bundled `agent-box-manage.sh` for ongoing management.
- Use `HERMES_HOST_COMMANDS=1` only when the trusted Telegram admin should be able to run
  named host commands through `host-shell`.
- Treat root passwords as one-time handoff material. Save them in local `credentials.txt`
  if needed, never in committed docs.

## Verification

Before handing work back, run syntax checks for edited shell scripts:

```bash
bash -n <script>
```

Prefer `shellcheck` when available. New user-facing flows should be documented in the
skill's SKILL.md and README.md.
