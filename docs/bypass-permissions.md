# Skipping Claude's permission prompts in the sandbox

Notes on running Claude in bypass-permissions mode (`--dangerously-skip-permissions`) inside the demo's cloud sandbox. `launch.sh -y` implements the part that needs implementing (the VS Code panel). See [Tested in a cloud sandbox](#tested-in-a-cloud-sandbox) for what was checked and what turned out different from the research below.

Researched 2026-10-17 against `sbx` v0.48.0, the [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server) and the Claude Code docs.

## Three ways Claude runs here

The sandbox runs Claude in three places, and each picks its permission mode differently.

| Where | How it starts | Bypass today? | What enables it |
|---|---|---|---|
| sbx agent session (`sbx --cloud attach NAME`) | `sbx --cloud run … claude` in `launch.sh` | Yes, per Docker's docs | Nothing to do |
| `claude` typed in code-server's integrated terminal | Plain `claude` | Yes in a cloud sandbox: `sbx` seeds `~/.claude/settings.json` (see below). The research assumed not. | `~/.claude/settings.json` in the sandbox |
| Claude panel in VS Code (Spark icon) | The Claude Code extension in code-server | No. `launch.sh -y` enables it. | code-server user `settings.json` in the sandbox |

### sbx agent session

Docker's [Claude Code agent page](https://docs.docker.com/ai/sandboxes/agents/claude-code/) says that with no extra arguments the sandbox runs `claude --dangerously-skip-permissions`. Arguments after `--` that start with `-` are appended to that default. A bare word replaces it, and you then have to pass the flag yourself:

```bash
sbx --cloud run -d --name NAME claude -- -c                                   # claude --dangerously-skip-permissions -c
sbx --cloud run -d --name NAME claude -- --dangerously-skip-permissions agents  # keep the flag with a subcommand
```

`launch.sh` passes nothing after `--`, so the default applies. The Docker page describes local `sbx run`. That cloud sandboxes use the same default is assumed, not checked.

### `claude` in the integrated terminal

> **Superseded by testing.** In a cloud sandbox `sbx` already writes `defaultMode: bypassPermissions` to this file on every start, so there is nothing to add. The text below is the general Claude Code behaviour, kept for reference. See [Tested in a cloud sandbox](#tested-in-a-cloud-sandbox).

A terminal session takes its mode from the first of these that applies ([permission modes](https://code.claude.com/docs/en/permission-modes)):

1. `--permission-mode` or `--dangerously-skip-permissions` on the command line
2. `permissions.defaultMode` in a settings file
3. The built-in default (auto on current versions)

To make plain `claude` start in bypass mode, merge this into `~/.claude/settings.json` **inside the sandbox**:

```json
{
  "permissions": { "defaultMode": "bypassPermissions" },
  "skipDangerousModePermissionPrompt": true
}
```

- It has to be the user file. Claude Code ignores `"bypassPermissions"` in a project's `.claude/settings.json` or `.claude/settings.local.json` and starts in Manual mode instead, so a cloned repo can't turn it on.
- Your host's `~/.claude` is not copied into the sandbox, so setting it locally does nothing.
- `skipDangerousModePermissionPrompt` skips the one-time "accept responsibility" dialog shown on the first bypass session. Without it, the dialog appears once and accepting it writes the same key.
- Claude Code refuses bypass mode as root. The kit runs code-server as uid 1000 (`agent`), so this doesn't apply.

### Claude panel in VS Code

Conversations started from the extension don't use `permissions.defaultMode`. They use the extension's own settings ([VS Code extension settings](https://code.claude.com/docs/en/vscode)):

| Setting | Effect |
|---|---|
| `claudeCode.allowDangerouslySkipPermissions` | Adds Bypass permissions to the mode selector (default `false`) |
| `claudeCode.initialPermissionMode` | Starting mode for new conversations: `default`, `plan`, `acceptEdits` or `bypassPermissions` |

VS Code reads `initialPermissionMode` from user settings only and ignores workspace values. In code-server, user settings live at `~/.local/share/code-server/User/settings.json`, which the kit already ships with six keys of its own. Add:

```json
{
  "claudeCode.allowDangerouslySkipPermissions": true,
  "claudeCode.initialPermissionMode": "bypassPermissions"
}
```

## Tested in a cloud sandbox

Checked on `sbx` v0.48.0-rc4 with an `anthropic` OAuth secret stored, 2026-10-17.

1. **The terminal `claude` is already in bypass mode.** A fresh sandbox has `~/.claude/settings.json` containing `"permissions": {"defaultMode": "bypassPermissions"}`, `bypassPermissionsModeAccepted: true` and an `apiKeyHelper`. `claude -p ... --output-format stream-json --verbose` reports `permissionMode: bypassPermissions`. Nothing to enable.
2. **`sbx` rewrites that file on every start.** After a stop and start it was regenerated: `defaultMode` and `bypassPermissionsModeAccepted` came back, but an extra key added by hand (`skipDangerousModePermissionPrompt`) was gone. Edits to `~/.claude/settings.json` are not durable, and `-y` doesn't make any.
3. **`jq` and `python3` exist in the sandbox**, and the agent runs as uid 1000, so the merge needs no extra install and bypass mode isn't refused as root.
4. **The kit's `User/settings.json` is not rewritten on restart.** The two `claudeCode.*` keys added by `-y` were still there afterwards, alongside the kit's six keys.
5. **The extension defines both settings** (`claudeCode.allowDangerouslySkipPermissions`, `claudeCode.initialPermissionMode` with `bypassPermissions` in its enum) in its `package.json` for version 2.1.302.

Not checked: that the panel really opens in Bypass permissions mode after `-y`. That needs the browser UI, and only the settings were inspected. Also unchecked: whether the cloud sbx agent session uses `--dangerously-skip-permissions` as the Docker docs say for local runs.

## What `-y` does

`launch.sh -y` runs, after the health check, one `sbx --cloud exec` that merges the two `claudeCode.*` keys into `~/.local/share/code-server/User/settings.json` with `jq`. It merges rather than overwrites, because the kit ships its own keys in that file. If `jq` fails, the file is left untouched and the script exits with an error.

Without `-y`, the script changes nothing, so the terminal and the sbx session still skip prompts because `sbx` does. The script has no switch to turn that off.

An alternative is forking the kit and shipping the two keys in its `files/home/.local/share/code-server/User/settings.json`, then passing the fork with `-k`. That avoids the `exec` step but needs a maintained fork.

## Risk

The Claude Code docs say to use bypass mode only in containers or VMs without internet access. This sandbox has allowlisted egress, and the kit exposes code-server with `--auth none` on a public URL. Bypass mode adds little to that exposure, since anyone holding the URL already has a terminal in the sandbox. The real change is that Claude acts on prompt-injected content (from a cloned repo, a fetched page, a dependency) without asking, using the credentials the proxy injects. Keep the TTL short, store only the secrets the demo needs, and tear the sandbox down when finished.

## Sources

- [Docker Sandboxes: Claude Code agent](https://docs.docker.com/ai/sandboxes/agents/claude-code/)
- [Claude Code: Choose a permission mode](https://code.claude.com/docs/en/permission-modes)
- [Claude Code: Configure permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code: Use Claude Code in VS Code](https://code.claude.com/docs/en/vscode)
- [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server)
