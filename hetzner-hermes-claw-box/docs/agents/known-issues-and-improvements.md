# Known Issues & Improvements — hetzner-agent-box skill

Living document. Seeded from the 2026-09-06 live deployment of `openclaw-box`
(delete old box → fresh install → Mac-config clone → Tailscale Serve → model/provider
parity debugging). Provider- and model-agnostic: substitute whatever agent runtime
and model provider you use. Each item lists status and the fix it needs. No secrets
in this file, ever.

## Fixed on 2026-09-06 (keep as regression guard)

- **`TAILSCALE_AUTH_KEY` was never forwarded to the box** — headless install
  would hang forever on `tailscale up` browser login. Fixed in `d5f8659`.
- **Remote installer always pulled from the GitHub raw URL** — serves the stale
  script until the repo is pushed. Fixed in `d5f8659`: local repo script is
  scp'd when present, curl fallback otherwise.
- **cx23 had no fsn1 capacity at deploy time** (nbg1 only). Type/location
  validation caught it correctly; operator switched manually. See bug #5.
- **Wrong SSH key passphrase hung ssh-add forever** (unbounded askpass retry
  loop, 3+ min until killed). Worked around live by minting a fresh
  no-passphrase deploy key. Real fix still owed: bug #1 below.
- **Zsh gotchas in ops tooling**: unquoted `$VAR` doesn't word-split (use a
  function); rsync needs no IPv4 brackets; heredoc f-strings must interpolate.
  The clone script in this repo's history hit all three — review any
  hand-written ops script with `bash -n` AND `zsh -n` before running.

## Bugs to fix (priority order)

1. **Wrong SSH key passphrase hangs forever.** Verify with
   `ssh-keygen -y -P "$pass" -f "$key"` before ssh-add; fail fast with a clear
   error. Preflight should also detect key/passphrase drift between an old
   `.env` and an existing key (both directions).
2. **No preflight validation.** Every stall tonight was detectable before
   spending a cent. Add a `preflight`/`doctor` mode (and run it at install
   start) that checks: provider API token via a live API call **issued from a
   clean network path** (see env note #1), SSH key + passphrase match,
   required tools present, type/location capacity via `/server_types`, and
   `.env` value sanity (a 6-character "API key" fragment shipped all the way
   to the box because nothing validated length/format).
3. **Onboarding wizard writes a single-model allowlist.** The VPS installer's
   best-effort non-interactive onboarding wrote
   `agents.defaults.modelPolicy.allow = [<one model>]`, which made the
   dashboard's model picker show only *allowlist ∪ default* (one or two
   models) while the gateway catalog had everything, auth intact. Silent,
   confusing, and looks like a credential failure. The installer must never
   write a restrictive `modelPolicy` — leave it absent (absent = all provider
   models selectable). Diagnosis path that found it:
   `openclaw models status --json` → `.allowed`.
4. **Onboarding leaves tokenless `setup-*` auth profiles in TWO stores.**
   The wizard created several credential-less auth profiles: some in
   `openclaw.json` (`auth.profiles`), some in the **per-agent sqlite auth
   store** (`~/.openclaw/agents/<id>/agent/openclaw-agent.sqlite`). Deleting
   the config section does NOT clean the agent store — the UI keeps reading
   it. Cleanup requires `openclaw models auth logout --agent <id> --yes
   <profileId>` per profile per agent. The installer should create exactly
   one profile, in one store, with the real key.
5. **Recommended default ignores live capacity.** Default type/location pair
   failed availability. When prompting (and in preflight), fetch
   `/server_types` and default to a location that is actually `available`.
6. **Legacy exec-approvals file blocks first messages.** Fresh installs ship
   a legacy `exec-approvals.json`; the gateway then rejects messages with
   `ExecApprovalsMigrationRequiredError` until migrated. `openclaw doctor
   --fix` CANNOT do it under a systemd user service — its maintenance-mode
   ownership check fails even with the service stopped, `XDG_RUNTIME_DIR`
   set, and the absolute binary path. Working remedy: rename the legacy file
   aside, import with `openclaw approvals set --file <legacy>`, restart.
   The installer should ship the migrated form so this never triggers.
7. **Provider env var does not authenticate the model list.** A working key
   in the service env file is NOT picked up as model auth
   (`auth.shellEnvFallback.enabled: false`); after any auth-store cleanup the
   catalog shows zero authed models. Automation path that works:
   `printf '%s' "$KEY" | openclaw models auth paste-token --provider <p>
   --agent <a>` per agent (`login` demands a TTY). The installer/maintenance
   helper should run paste-token itself for every configured agent.
8. **Non-interactive stdin contract is undocumented and brittle.** Install
   reads prompts in a specific order (optional channel token → literal
   `CREATE`); piping `y` silently reports "server creation cancelled" without
   saying what it expected. Fixes: error message says `type CREATE to
   confirm`; a real `--non-interactive` mode documents the full sequence.
9. **Root password printed once to stdout only.** Add `--credentials-file`
   (600, gitignore-checked) to persist it at handoff.
10. **`ssh -tt` swallows piped-stdin EOF.** Remote prompts under `ssh -tt`
    get a pty; when the local pipe is exhausted the remote `read` blocks
    forever (observed: install frozen on a channel-token prompt). Workaround
    used live: inject the newline into the remote pty via TIOCSTI as root.
    Installer should avoid `-tt` for non-interactive flows or feed every
    prompt explicitly.

## Improvements (nice-to-have)

- **Box-clone / adopt runbook — now proven, write it down.** The full working
  procedure from tonight: surgical config merge (base = box install, overlay =
  Mac `agents`/`models`/`plugins`/`tools`/`skills` **and `auth.profiles`**,
  with absolute-path rewrite), workspaces rsync'd excluding `memory/`, empty
  memory scaffolding recreated, **chown to the service user BEFORE creating
  scaffolding inside rsync'd dirs** (rsync as root leaves root-owned dirs),
  `plugin-skills/` + personal skills dirs synced, `gateway.trustedProxies`
  set for the loopback serve proxy, per-agent auth store cleaned then
  re-added via paste-token. One script, one flag: `--from <mac>`.
- **Expectation-setting for dashboard version asymmetry.** The current-gen
  web dashboard renders an unconditional per-chat "account selection" row in
  the model picker (source: `resolveChatAccountSelection` — no feature flag,
  no config to hide it). Older native apps predate it. Cloned setups will
  look slightly different from an older app; document this instead of
  debugging it twice.
- **Operator device pairing runbook.** First dashboard login on a new device
  needs a host-side `openclaw devices approve <id>`; the command needs the
  gateway token env sourced AND the CLI's absolute path under `runuser`
  (non-login shells lack the user's local bin). Two-line snippet in SKILL.md
  saves ten minutes.
- **Stale tailnet device entries.** After deleting a box its tailnet device
  entry lingers; a same-name successor gets `-1` suffixed. Document removal.
- **Old default key vs new default key.** Machines from earlier eras carry
  the old keypair plus a stale passphrase in an old `.env`. Preflight warns
  on configured-key ≠ current-default with passphrase mismatch.
- **`.env` quoting convention.** Values written quoted; ad-hoc `grep|cut`
  readers keep quotes and break auth. Document "source the file; never
  grep/cut it".

## Environment notes (not skill bugs; affect the workflow)

1. **A proxied client can fake provider-auth failures.** Testing a model
   provider's API key from a machine whose egress goes through an
   authenticated local proxy produced `401 token expired or incorrect` for a
   key that was perfectly valid from the box's direct egress. Four "broken
   credentials" tonight, zero actually broken — every failure was the path
   (proxy mangling, header-file printf, quote-keeping extraction, pty EOF).
   Rule: **validate credentials from the box, not through your proxy.**
2. **Codex CLI cannot connect through the gateway's authenticated egress
   proxy** (websocket CONNECT 407 retry loops). Delegation fallback:
   the alternate sanctioned coding agent; keep patch specs small and
   finish harness details by hand when the agent dies on sandbox
   permissions (it rejects `/tmp` writes mid-task).
3. **Console copy of API tokens can grab the masked preview** (`XXXX…XXXX`).
   Terminal `read -s` into `.env` is the reliable path; steer operators
   there during setup.
4. **Agent CLI invocation under systemd user services**: non-login
   `runuser` shells lack the user's local bin (use absolute path or
   `bash -lc`), and most gateway commands need the secret env file sourced
   (config secret references don't resolve otherwise).
