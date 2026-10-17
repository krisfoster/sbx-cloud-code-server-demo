# Skipping Claude's permission prompts in the sandbox

Research notes on running Claude in bypass-permissions mode (`--dangerously-skip-permissions`) inside the demo's cloud sandbox. Nothing here is implemented in `launch.sh` yet, and none of it has been tested in a cloud sandbox. See [Open questions](#open-questions).

Researched 2026-10-17 against `sbx` v0.48.0, the [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server) and the Claude Code docs.

## Three ways Claude runs here

The sandbox runs Claude in three places, and each picks its permission mode differently.

| Where | How it starts | Bypass today? | What enables it |
|---|---|---|---|
| sbx agent session (`sbx --cloud attach NAME`) | `sbx --cloud run … claude` in `launch.sh` | Yes, per Docker's docs | Nothing to do |
| `claude` typed in code-server's integrated terminal | Plain `claude` | No, starts in the built-in default (auto) | `~/.claude/settings.json` in the sandbox |
| Claude panel in VS Code (Spark icon) | The Claude Code extension in code-server | No | code-server user `settings.json` in the sandbox |

### sbx agent session

Docker's [Claude Code agent page](https://docs.docker.com/ai/sandboxes/agents/claude-code/) says that with no extra arguments the sandbox runs `claude --dangerously-skip-permissions`. Arguments after `--` that start with `-` are appended to that default. A bare word replaces it, and you then have to pass the flag yourself:

```bash
sbx --cloud run -d --name NAME claude -- -c                                   # claude --dangerously-skip-permissions -c
sbx --cloud run -d --name NAME claude -- --dangerously-skip-permissions agents  # keep the flag with a subcommand
```

`launch.sh` passes nothing after `--`, so the default applies. The Docker page describes local `sbx run`. That cloud sandboxes use the same default is assumed, not checked.

### `claude` in the integrated terminal

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

## Ways to apply it

**A. Opt-in flag in `launch.sh` (recommended).** Add a flag such as `-y`. After the health check, `sbx --cloud exec` merges the keys above into both files. It must merge, not overwrite: the kit's `User/settings.json` has its own keys, and `~/.claude/settings.json` probably holds the credential proxy's auth setup (`claude` reports an `api_key_helper` auth method when an `anthropic` secret is stored).

**B. Fork the kit.** Put the two `claudeCode.*` keys in the fork's `files/home/.local/share/code-server/User/settings.json` and pass it with `-k`. This covers the VS Code panel only, so the terminal `claude` still needs the `exec` step from A.

## Open questions

These need a signed-in cloud sandbox to answer:

1. Does the cloud `claude` agent use the same `--dangerously-skip-permissions` default as local `sbx run`?
2. What does `~/.claude/settings.json` contain in a fresh sandbox, and is `jq` (or another JSON tool) available to merge into it?
3. Does the kit rewrite `User/settings.json` when a stopped sandbox starts again? If so, an `exec` edit is lost after a stop and start, and the setting would need to go in the kit (option B) or be reapplied on start.

## Risk

The Claude Code docs say to use bypass mode only in containers or VMs without internet access. This sandbox has allowlisted egress, and the kit exposes code-server with `--auth none` on a public URL. Bypass mode adds little to that exposure, since anyone holding the URL already has a terminal in the sandbox. The real change is that Claude acts on prompt-injected content (from a cloned repo, a fetched page, a dependency) without asking, using the credentials the proxy injects. Keep the TTL short, store only the secrets the demo needs, and tear the sandbox down when finished.

## Sources

- [Docker Sandboxes: Claude Code agent](https://docs.docker.com/ai/sandboxes/agents/claude-code/)
- [Claude Code: Choose a permission mode](https://code.claude.com/docs/en/permission-modes)
- [Claude Code: Configure permissions](https://code.claude.com/docs/en/permissions)
- [Claude Code: Use Claude Code in VS Code](https://code.claude.com/docs/en/vscode)
- [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server)
