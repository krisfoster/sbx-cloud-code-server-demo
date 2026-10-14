#!/usr/bin/env bash
#
# Launch a Docker cloud sandbox running the code-server kit (VS Code in the browser).
#
#   ./launch.sh [-n NAME] [-t TTL] [-s SIZE] [-k KIT] [-r REPO_URL] [-e KEY[=VALUE]]...
#
#   -n NAME  sandbox name (letters, numbers, hyphens; default: code-server-demo)
#   -t TTL   time to live, e.g. 2h, 90m (default: 4h; hard cap is 24h from creation)
#   -s SIZE  micro | small | medium | large | xl (default: medium = 4 vCPU / 8 GiB)
#   -k KIT   kit reference (default: the code-server kit in docker/sbx-kits-contrib)
#   -r URL   https git repo to clone into the workspace (public repos only)
#   -e VAR   env var for the sandbox, KEY=VALUE or bare KEY to copy it from your
#            shell (repeatable). Stored inside the sandbox; see README for secrets.
#
# Environment overrides: SBX_DEMO_NAME, SBX_DEMO_TTL, SBX_DEMO_SIZE, SBX_DEMO_KIT, SBX_DEMO_REPO

set -euo pipefail

NAME="${SBX_DEMO_NAME:-code-server-demo}"
TTL="${SBX_DEMO_TTL:-4h}"
SIZE="${SBX_DEMO_SIZE:-medium}"
KIT="${SBX_DEMO_KIT:-git+https://github.com/docker/sbx-kits-contrib.git#dir=code-server}"
REPO="${SBX_DEMO_REPO:-}"
PORT=8080
ENVS=()

while getopts "n:t:s:k:r:e:h" opt; do
  case $opt in
    n) NAME=$OPTARG ;;
    t) TTL=$OPTARG ;;
    s) SIZE=$OPTARG ;;
    k) KIT=$OPTARG ;;
    r) REPO=$OPTARG ;;
    e) ENVS+=("$OPTARG") ;;
    h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) exit 2 ;;
  esac
done

case $SIZE in
  micro)  CPUS=1;  MEM=2g ;;
  small)  CPUS=2;  MEM=4g ;;
  medium) CPUS=4;  MEM=8g ;;
  large)  CPUS=8;  MEM=16g ;;
  xl)     CPUS=16; MEM=32g ;;
  *) echo "Unknown size '$SIZE' (use micro, small, medium, large or xl)" >&2; exit 2 ;;
esac

EXTRA=()
if [ -n "$REPO" ]; then
  case $REPO in
    https://*) ;;
    *) echo "Repo must be an https:// URL (got '$REPO')." >&2; exit 2 ;;
  esac
  repo_host=${REPO#https://}; repo_host=${repo_host%%/*}
  case $repo_host in
    *@*) echo "Don't embed credentials in the repo URL." >&2; exit 2 ;;
  esac
  EXTRA+=(--allow-network "$repo_host")
fi

for e in ${ENVS[@]+"${ENVS[@]}"}; do
  key=${e%%=*}
  case $key in
    ''|[0-9]*|*[!A-Za-z0-9_]*) echo "Invalid env var name '$key' for -e." >&2; exit 2 ;;
  esac
  if [ "$key" = "$e" ] && [ -z "${!key+x}" ]; then
    echo "-e $key: not set in your shell. Use -e $key=VALUE or export it first." >&2; exit 2
  fi
  EXTRA+=(--env "$e")
done

command -v sbx >/dev/null || { echo "sbx not found. Install: https://docs.docker.com/ai/sandboxes/get-started/" >&2; exit 1; }

echo "==> Checking cloud sandbox access"
if ! existing=$(sbx --cloud ls -q 2>&1); then
  echo "$existing" >&2
  echo "Run 'sbx login' and try again." >&2
  exit 1
fi
if awk -F/ -v n="$NAME" '$NF == n { found = 1 } END { exit !found }' <<<"$existing"; then
  echo "A cloud sandbox named '$NAME' already exists. Run ./teardown.sh -n $NAME first, or pick another name with -n." >&2
  exit 1
fi

echo "==> Creating cloud sandbox '$NAME' ($SIZE, ttl $TTL)"
echo "    kit: $KIT"
echo "    The first create installs code-server and the Claude Code extension, so it can take a few minutes."
sbx --cloud run --detached \
  --name "$NAME" \
  --cpus "$CPUS" --memory "$MEM" \
  --ttl "$TTL" \
  --kit "$KIT" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  claude

echo "==> Publishing port $PORT"
sbx --cloud ports "$NAME" --publish "$PORT"

echo "==> Waiting for code-server to answer on :$PORT"
ready=0
for _ in $(seq 1 60); do
  if sbx --cloud exec "$NAME" curl -fsS -o /dev/null "http://localhost:$PORT/healthz" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 3
done
if [ "$ready" -ne 1 ]; then
  echo "code-server did not come up within 3 minutes. Log:" >&2
  sbx --cloud exec "$NAME" cat /tmp/code-server.log >&2 || true
  exit 1
fi

if [ -n "$REPO" ]; then
  echo "==> Cloning $REPO into the workspace"
  # The kit bakes the workspace path into its startup script as the last argument.
  ws=$(sbx --cloud exec "$NAME" sh -c 'tail -n 1 /home/agent/.local/bin/start-code-server.sh' | awk '{print $NF}' | tr -d '"\r')
  [ -n "$ws" ] || { echo "Could not determine the workspace path in the sandbox." >&2; exit 1; }
  sbx --cloud exec "$NAME" sh -c 'git clone -- "$1" "$2/$(basename "$1" .git)"' _ "$REPO" "$ws"
  echo "    Cloned into $ws/$(basename "$REPO" .git)"
fi

echo
echo "==> Ready. Public URL for port $PORT:"
sbx --cloud ports "$NAME"
cat <<MSG

WARNING: the kit runs code-server with --auth none. The URL above reaches a
full editor and terminal in the sandbox, so treat it as a secret and run
./teardown.sh -n $NAME when you are done.

Next: open the URL, then in the integrated terminal (Ctrl+\`) run 'claude' and
sign in. See README.md.
MSG
