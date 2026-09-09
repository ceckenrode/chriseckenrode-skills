# Workspace and policy recovery

Recovery is an explicit, future operator procedure. Installation, refresh,
maintenance, and sandbox inspection do not rename, merge, archive, or delete
workspaces. Do not begin by changing the sandbox mode or replacing managed state.

1. Quiesce affected OpenClaw sessions and stop or otherwise quiesce the affected
   service before copying or comparing data.
2. Preserve the managed configuration and state, both workspace trees (including
   git history and memory), and any stranded sandbox host-mounted directories.
   Keep the original recorded paths intact while investigating.
3. Compare the trees and managed records before merging. Identify conflicts in
   files, repository history, memory, agent IDs, workspace paths, and sandbox
   policy. A missing or empty destination is not permission to discard a source.
4. Choose the target path and update every reference to it: the agent record,
   generated configuration, workspace notes, scripts or service settings, and
   any approval entries whose project prefix is changing.
5. Verify continuity with the service quiesced and then with a controlled session:
   check repository history, memory, permissions, agent identity, recorded
   workspace, sandbox mode/backend, and intended git/gh operations. Only after
   continuity is verified may an operator archive a duplicate. Archiving is not
   automatic deletion; retain a recoverable copy and document its location.

An Incus export does **not** include the external host workspace disk. Preserve
host paths explicitly as a separate recovery input. Retained Incus groups,
containers, and packages may remain installed while an agent uses host-authoritative
sandbox-off execution; removing that infrastructure is a separate future action.

## Approval paths during recovery

Fresh installs seed the installed git and gh executables through the supported
`openclaw approvals allowlist` CLI. Use exact system binary grants, for example
`/usr/bin/git` and the verified absolute path returned by `command -v gh` on the
box. Quote every path passed to the CLI.

If a project-specific executable needs an additional grant, use a deliberately
narrow, quoted glob after comparing the new recorded workspace prefix, for
example:

```text
'/home/<service-user>/workspace-<agent-id>/tracker/**'
```

That glob does not survive a change to the `<agent-id>` prefix, and it does not
confine git's current working directory. Re-scope it explicitly after recovery;
never prescribe or create an automatic `~/workspace-*/**` grant. An unmatched
command must fail closed; the agent should report the missing capability and an
operator should add it with the supported CLI.

The approval wrapper remains scoped to the named initial agent. Do not broaden it
as a shortcut for recovery. Approval edits, workspace migration, sandbox-policy
changes, and any deploy-key registration described here are future explicit
operator actions and are outside this offline implementation's verification.
