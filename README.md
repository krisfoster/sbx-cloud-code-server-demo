# sbx cloud code-server demo

Launch a Docker **cloud sandbox** that runs VS Code in your browser (code-server) with the Claude Code extension, using the [`code-server` kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server) from `docker/sbx-kits-contrib`. Open the URL, open Claude, sign in.

## Requirements

- `sbx` installed and signed in (`sbx login`). Written against `v0.47.0-rc2`, re-checked on `v0.48.0-rc4`, help output re-checked on `v0.48.0`.
- Access to Docker cloud sandboxes (`sbx --cloud ls` should not error).

## Use

```bash
./launch.sh                 # create the sandbox, publish port 8080, print the URL
./launch.sh -n my-demo -t 2h -s large
./launch.sh -r https://github.com/owner/repo.git   # also clone a repo into the workspace
./launch.sh -e MY_VAR=value -e HOME_TOKEN            # pass env vars (see below)
./launch.sh -y                                       # no permission prompts in the Claude panel (see below)
./teardown.sh               # delete it when you are done (-n NAME for a non-default name)
```

| Option | Env override | Default | Meaning |
| --- | --- | --- | --- |
| `-n NAME` | `SBX_DEMO_NAME` | `code-server-demo` | Sandbox name. `teardown.sh` reads the same variable. |
| `-t TTL` | `SBX_DEMO_TTL` | `4h` | Time to live, e.g. `90m`, `2h`. Hard cap 24h from creation. |
| `-s SIZE` | `SBX_DEMO_SIZE` | `medium` | `micro` (1 vCPU/2 GiB), `small` (2/4), `medium` (4/8), `large` (8/16), `xl` (16/32). |
| `-k KIT` | `SBX_DEMO_KIT` | `git+https://github.com/docker/sbx-kits-contrib.git#dir=code-server` | Kit reference. The kit's published OCI artifact `docker.io/sbx/code-server-kit:latest` should also work but is untested here. |
| `-r URL` | `SBX_DEMO_REPO` | none | Public `https://` repo to clone into the workspace. |
| `-e VAR` | none | none | Env var, `KEY=VALUE` or bare `KEY`. Repeatable. |
| `-y` | none | off | Turn off permission prompts in the Claude VS Code panel. See [Permission prompts](#permission-prompts). |

`./launch.sh -h` prints the same summary. The script refuses to run if a cloud sandbox with that name already exists.

Cloud sandboxes have no host workspace, so a local directory can't be passed in. Use `-r` (or `SBX_DEMO_REPO`) to clone a public `https://` repo instead. It lands in a subfolder of the workspace named after the repo, and the repo's host is added to the sandbox's allowed egress. Private repos are untested: store a `github` secret first (see [Secrets](#secrets)) and the proxy may authenticate the clone.

`launch.sh` runs these steps:

1. `sbx --cloud run -d --name NAME --cpus N --memory M --ttl TTL --kit <code-server kit> claude`, plus `--allow-network <repo host>` for `-r` and `--env` for each `-e`. This creates a cloud sandbox on the built-in `claude` agent with the kit layered on. The kit is a mixin that requires `claude`, so the VS Code extension shares the sandbox's Claude credentials.
2. `sbx --cloud ports NAME --publish 8080`: asks the cloud control plane for a public URL for code-server's port. The kit now declares port 8080 itself, which publishes it automatically for local sandboxes. Whether that alone gives a public URL in the cloud is untested, so the script still publishes it explicitly.
3. Polls `http://localhost:8080/healthz` inside the sandbox for up to 3 minutes. If code-server never answers, it prints `/tmp/code-server.log` and exits.
4. With `-r`: reads the workspace path from the kit's `start-code-server.sh` and runs `git clone` into it.
5. With `-y`: merges two `claudeCode.*` keys into code-server's user `settings.json` inside the sandbox.
6. `sbx --cloud ports NAME` to print the URL.

## Sign in to Claude

### Option 1: store the credential first (no login in the sandbox)

Store an Anthropic credential as an `sbx` secret **before** running `launch.sh`. The sandbox gets a placeholder and the cloud proxy injects the real credential, so there is nothing to sign in to.

```bash
# Claude subscription: runs the OAuth flow in your browser on your machine
sbx --cloud secret set anthropic --oauth

# or an Anthropic API key, piped in so it stays out of shell history
echo "$ANTHROPIC_API_KEY" | sbx --cloud secret set anthropic
op read 'op://Private/Anthropic/api-key' | sbx --cloud secret set anthropic   # from 1Password
```

- `--oauth` is account-scoped: `--sandbox` is rejected, so every cloud sandbox you create afterwards uses it. Remove it with `sbx --cloud secret rm anthropic`.
- Secrets are applied when a sandbox is **created**. One that already exists keeps showing "Not logged in", even after a stop and start. Tear it down and relaunch.
- Tested with the `claude` CLI only (`claude -p` works with no login prompt). With a secret in place `claude` reports an `api_key_helper` auth method and warns that claude.ai connectors (org MCP integrations) are disabled because another auth source takes precedence.
- The API key form is untested.

### Option 2: sign in interactively

1. Open the printed URL in your browser. The workspace opens on launch.
2. Open the integrated terminal (Ctrl+`) and run `claude`, or click the Claude **Spark** icon in the editor toolbar (top right). The kit sets the Claude panel to open in the sidebar.
3. If prompted, choose a login method and open the sign-in link in your local browser.
4. The last step redirects to `http://localhost:<port>/callback?code=...`. That listener runs inside the sandbox, but `localhost` in your browser is your own machine, so the page fails to load. Copy the full URL from the address bar and paste it (or its `code` value) back into the sandbox terminal. It still works, because the code is in the URL.

> [!warning]
> The kit starts code-server with `--auth none`. Upstream treats that as fine because a local sandbox only publishes to `localhost`. In a cloud sandbox the published port gets a public URL, so anyone holding that URL has an editor and terminal inside the sandbox. Treat the URL as a secret, keep the TTL short, and tear down when finished. For anything beyond a demo, fork the kit and add a password to the startup command.

## Secrets

Prefer `sbx` secrets over env vars. The sandbox never sees the real value: the cloud proxy injects the credential into outbound requests to the matching service. Store them on your host before running `launch.sh`. They apply to all sandboxes by default, or add `--sandbox NAME` to scope one. A secret reaches only sandboxes created after it is stored.

With `--cloud`, `sbx` stores the value itself: `--command` and `--ref` are ignored and you get an `Enter secret:` prompt instead. Resolve the value yourself and pipe it in. It is a snapshot, so re-run the command when the token rotates.

```bash
# GitHub, reusing your gh login
gh auth token | sbx --cloud secret set github

# The same, from 1Password (needs an authenticated `op` CLI)
op read 'op://Private/GitHub/token' | sbx --cloud secret set github

# Anthropic: see "Sign in to Claude" above
echo "$ANTHROPIC_API_KEY" | sbx --cloud secret set anthropic

# Another provider, piping the value in so it stays out of shell history
echo "$OPENAI_API_KEY" | sbx --cloud secret set openai

sbx --cloud secret ls       # list stored secrets
sbx --cloud secret rm github   # remove a global secret
```

Built-in services in v0.48.0 are `anthropic`, `copilot`, `cursor`, `devin`, `droid`, `github`, `google`, `groq`, `mistral`, `nebius`, `openai`, `openrouter` and `xai`. For an API that isn't built in, `sbx --cloud secret set-custom --host api.example.com --env API_KEY --value ...` (experimental) gives the sandbox a placeholder and has the proxy set the real value in a header for that host (`Authorization: Bearer …` unless you pass `--header`/`--format`). In cloud mode `--host` takes exact DNS names only, no wildcards.

## Environment variables

Pass variables with `-e`, repeated as needed. `KEY=VALUE` sets a value; a bare `KEY` copies it from your shell, which keeps the value out of the command line you type.

```bash
export MY_TOKEN=...
./launch.sh -e MY_TOKEN -e LOG_LEVEL=debug
```

They are baked into the sandbox and visible to its agent session. Anyone with the published URL has a terminal there and can read them, so use env vars for non-sensitive config and the secrets above for credentials. With `sbx` directly, `--env-file` is also available.

## Permission prompts

Claude runs in three places in the sandbox, and in a cloud sandbox two of them already skip permission prompts:

| Where | Prompts off by default? |
| --- | --- |
| `sbx --cloud attach NAME` (the sbx agent session) | Yes |
| `claude` in the integrated terminal | Yes. `sbx` writes `permissions.defaultMode: bypassPermissions` to `~/.claude/settings.json` on every start, and `claude` reports `permissionMode: bypassPermissions`. |
| Claude panel in VS Code (Spark icon) | No. The extension ignores that file and has its own settings. |

`-y` is the opt-in for the third one. It merges `claudeCode.allowDangerouslySkipPermissions` and `claudeCode.initialPermissionMode: bypassPermissions` into `~/.local/share/code-server/User/settings.json` in the sandbox, keeping the kit's own keys, and the change survives a stop and start.

```bash
./launch.sh -y
```

Dangerous: Claude then edits files and runs commands without asking, using the credentials the proxy injects. A cloned repo, a fetched page or a dependency can steer it with prompt injection. Keep the TTL short and store only the secrets the demo needs. Details and caveats in [docs/bypass-permissions.md](docs/bypass-permissions.md).

## Useful commands

```bash
sbx --cloud ls                                   # list cloud sandboxes
sbx --cloud ports code-server-demo               # show the public URL again
sbx --cloud exec code-server-demo cat /tmp/code-server.log
sbx --cloud attach code-server-demo              # terminal into the agent
sbx --cloud ttl code-server-demo                 # show the remaining TTL
sbx --cloud ttl +2h code-server-demo             # extend the TTL (24h hard cap)
```

## Status

Written from the kit README and `sbx --cloud ... --help`, then partly checked on `sbx` v0.48.0-rc4. Every command and flag the scripts and this README use was re-checked against `sbx --cloud … --help` on v0.48.0. Last compared against the upstream kit (`spec.yaml`, README) on 2026-10-17. Checked items below have been run; unchecked ones have not.

- [x] `--kit` with a `git+https` reference works on `sbx --cloud run`
- [x] The published URL answers (`/healthz` returns 200)
- [x] `-r` clones a public repo into the workspace
- [x] `-e` variables appear in the sandbox shell
- [x] `sbx --cloud secret set anthropic --oauth` lets `claude -p` run in a new sandbox with no login
- [x] `claude` in the terminal starts in `bypassPermissions` with no flags (checked with `claude -p ... --output-format stream-json`)
- [x] `-y` writes both `claudeCode.*` keys, keeps the kit's keys, and the keys survive a stop and start
- [ ] The Claude panel actually starts with Bypass permissions selected after `-y` (settings checked, UI not)
- [ ] The workspace and Claude extension render correctly in the browser
- [ ] Interactive `claude` login from the integrated terminal completes
- [ ] `echo $KEY | sbx --cloud secret set anthropic` (API key) works in a new sandbox
- [ ] A `github` secret lets `-r` clone a private repo

## Further docs

- [Skipping Claude's permission prompts](docs/bypass-permissions.md): what runs where, what was tested, and the risks of `-y`

## Sources

- [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server)
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/)
