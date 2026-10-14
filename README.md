# sbx cloud code-server demo

Launch a Docker **cloud sandbox** that runs VS Code in your browser (code-server) with the Claude Code extension, using the [`code-server` kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server) from `docker/sbx-kits-contrib`. Open the URL, open Claude, sign in.

## Requirements

- `sbx` installed and signed in (`sbx login`). Written against `v0.47.0-rc2`.
- Access to Docker cloud sandboxes (`sbx --cloud ls` should not error).

## Use

```bash
./launch.sh                 # create the sandbox, publish port 8080, print the URL
./launch.sh -n my-demo -t 2h -s large
./launch.sh -r https://github.com/owner/repo.git   # also clone a repo into the workspace
./launch.sh -e MY_VAR=value -e HOME_TOKEN            # pass env vars (see below)
./teardown.sh               # delete it when you are done
```

Cloud sandboxes have no host workspace, so a local directory can't be passed in. Use `-r` (or `SBX_DEMO_REPO`) to clone a public `https://` repo instead. It lands in a subfolder of the workspace named after the repo, and the repo's host is added to the sandbox's allowed egress. Private repos are untested: store a `github` secret first (see [Secrets](#secrets)) and the proxy may authenticate the clone.

`launch.sh` runs three things:

1. `sbx --cloud run --detached --name NAME --kit <code-server kit> claude`: creates a cloud sandbox on the built-in `claude` agent with the kit layered on. The kit is a mixin that requires `claude`, so the VS Code extension shares the sandbox's Claude setup.
2. `sbx --cloud ports NAME --publish 8080`: asks the cloud control plane for a public URL for code-server's port.
3. A health check against code-server inside the sandbox, then `sbx --cloud ports NAME` to print the URL.

## Sign in to Claude

1. Open the printed URL in your browser. The workspace opens on launch.
2. Open the integrated terminal (Ctrl+`) and run `claude`, or click the Claude (Spark) icon in the sidebar once.
3. If prompted, choose a login method, open the sign-in link in your local browser and paste the code back into the terminal.

> [!warning]
> The kit starts code-server with `--auth none`. In a cloud sandbox the published port gets a public URL, so anyone holding that URL has an editor and terminal inside the sandbox. Treat the URL as a secret, keep the TTL short, and tear down when finished. For anything beyond a demo, fork the kit and add a password to the startup command.

## Secrets

Prefer `sbx` secrets over env vars. The sandbox never sees the real value: the cloud proxy injects the credential into outbound requests to the matching service. Store them on your host before running `launch.sh`. They apply to all sandboxes by default, or add `--sandbox NAME` to scope one.

With `--cloud`, `sbx` stores the value itself: `--command` and `--ref` are ignored and you get an `Enter secret:` prompt instead. Resolve the value yourself and pipe it in. It is a snapshot, so re-run the command when the token rotates.

```bash
# GitHub, reusing your gh login
gh auth token | sbx --cloud secret set github

# The same, from 1Password (needs an authenticated `op` CLI)
op read 'op://Private/GitHub/token' | sbx --cloud secret set github

# Another provider, piping the value in so it stays out of shell history
echo "$OPENAI_API_KEY" | sbx --cloud secret set openai

sbx --cloud secret ls       # list stored secrets
sbx --cloud secret rm github   # remove a global secret
```

Built-in services include `anthropic`, `github`, `openai`, `google`, `groq`, `mistral` and `openrouter`. For an API that isn't built in, `sbx --cloud secret set-custom --host api.example.com --env API_KEY --value ...` (experimental) gives the sandbox a placeholder and has the proxy add the real header for that host.

## Environment variables

Pass variables with `-e`, repeated as needed. `KEY=VALUE` sets a value; a bare `KEY` copies it from your shell, which keeps the value out of the command line you type.

```bash
export MY_TOKEN=...
./launch.sh -e MY_TOKEN -e LOG_LEVEL=debug
```

They are baked into the sandbox and visible to its agent session. Anyone with the published URL has a terminal there and can read them, so use env vars for non-sensitive config and the secrets above for credentials. With `sbx` directly, `--env-file` is also available.

## Useful commands

```bash
sbx --cloud ls                                   # list cloud sandboxes
sbx --cloud ports code-server-demo               # show the public URL again
sbx --cloud exec code-server-demo cat /tmp/code-server.log
sbx --cloud attach code-server-demo              # terminal into the agent
sbx --cloud ttl code-server-demo +2h             # extend the TTL (24h hard cap)
```

## Status

Written from the kit README and `sbx --cloud ... --help`. Not yet run end to end: see the checklist below before relying on it.

- [ ] `--kit` with a `git+https` reference works on `sbx --cloud run`
- [ ] The published URL is reachable and shows the workspace
- [ ] `claude` login completes from the integrated terminal
- [ ] `-r` clones into the workspace (and a private repo with a `github` secret)
- [ ] `-e` variables appear in the sandbox shell
- [ ] Piping a token into `sbx --cloud secret set github` lets a private `-r` clone succeed

## Sources

- [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server)
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/)
