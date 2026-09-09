# GitHub bootstrap

This is the focused procedure for the optional, shared-account GitHub setup on an
OpenClaw box. Enter it from a private, interactive terminal after installation
and registration:

```bash
./agent-box-manage.sh github-bootstrap --box NAME
```

The manager accepts no token, agent, or group argument and does not source local
secret environment files. The box-side command requires a controlling TTY and a
usable managed installation. It is opt-in on every run.

## Credential choices

The manager first asks whether to copy an existing local GitHub CLI credential;
the default is **no**. If accepted, it checks that local `gh auth token` returns a
non-empty token, then pipes the token over the SSH session to a mode-600 staging
file. The token is never placed in an argument, displayed, or written to logs.
If no usable local credential exists, or the prompt is declined, enter the token
manually in the box's private terminal prompt. A failed transfer or login is
nonzero and can be retried; prior usable credentials are preserved.

The box stores the protected token file at the service account's configured
secrets location and runs GitHub CLI login followed by `gh auth setup-git`. The
final check starts a fresh process with `GH_TOKEN`, `GITHUB_TOKEN`, and related
token variables absent. It verifies `gh auth status`, the API identity, helper
resolution, and noninteractive credential retrieval. A successful check proves
that persisted auth works without an exported token; it does not prove access to
every repository.

GitHub authentication choices have different limits:

- A classic token needs only the scopes required by the intended operations;
  `repo` is broader than a read-only use case and should not be granted without
  an operator decision.
- A fine-grained token should be limited to the intended owner and selected
  repositories, with only the required repository permissions. It may not work
  for organization-wide operations, repository selection outside its scope,
  some API endpoints, or workflows that require unavailable account or
  organization permissions. Test the actual operation and report the limitation.
- A token's successful `auth status` is not proof that clone, push, releases,
  workflow administration, or organization access will succeed.

The bootstrap uses the shared service account. Git identity is separate: each
operator must provide their own name and email when prompted; any existing local
values may be offered as generic defaults, but are not assumed.

## Optional SSH authentication

SSH setup is offered separately from token login. If selected, the service
account uses the dedicated key `/home/openclaw/.ssh/github_ed25519`. An existing
private key is never replaced. If its public file is absent, it is derived and
the private/public fingerprints must match before continuing. The SSH config
change is limited to the marked block:

```text
# openclaw-vps github-bootstrap
Host github.com
  IdentityFile /home/openclaw/.ssh/github_ed25519
  IdentitiesOnly yes
# end openclaw-vps github-bootstrap
```

Conflicting `github.com` identity configuration outside that block fails closed.
Before adding a `known_hosts` entry, the box scans GitHub's ed25519 and RSA keys,
computes SHA-256 fingerprints, and compares them with trusted published GitHub
fingerprints. Only verified, deduplicated entries are appended; strict host-key
checking is retained. A scan or fingerprint mismatch writes no entry.

## Repository deploy keys

Registering a deploy key for a particular repository, choosing read-only versus
read-write access, and confirming the repository owner are **future explicit
operator actions**. This offline implementation does not register deploy keys,
choose repositories, or claim that any repository is reachable. Do not paste a
repository name or key into committed examples. After an operator registers a
key, they must test the intended repository operation and record its access level.
