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
./teardown.sh               # delete it when you are done
```

Cloud sandboxes have no host workspace, so a local directory can't be passed in. Use `-r` (or `SBX_DEMO_REPO`) to clone a public `https://` repo instead. It lands in a subfolder of the workspace named after the repo, and the repo's host is added to the sandbox's allowed egress. Private repos are not supported by the script.

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

## Sources

- [code-server kit](https://github.com/docker/sbx-kits-contrib/tree/main/code-server)
- [Docker Sandboxes docs](https://docs.docker.com/ai/sandboxes/)
