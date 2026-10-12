#!/usr/bin/env bash
#
# Launch a Docker cloud sandbox running the code-server kit (VS Code in the browser).
#
#   ./launch.sh [-n NAME] [-t TTL] [-s SIZE] [-k KIT]
#
#   -n NAME  sandbox name (letters, numbers, hyphens; default: code-server-demo)
#   -t TTL   time to live, e.g. 2h, 90m (default: 4h; hard cap is 24h from creation)
#   -s SIZE  micro | small | medium | large | xl (default: medium = 4 vCPU / 8 GiB)
#   -k KIT   kit reference (default: the code-server kit in docker/sbx-kits-contrib)
#
# Environment overrides: SBX_DEMO_NAME, SBX_DEMO_TTL, SBX_DEMO_SIZE, SBX_DEMO_KIT

set -euo pipefail

NAME="${SBX_DEMO_NAME:-code-server-demo}"
TTL="${SBX_DEMO_TTL:-4h}"
SIZE="${SBX_DEMO_SIZE:-medium}"
KIT="${SBX_DEMO_KIT:-git+https://github.com/docker/sbx-kits-contrib.git#dir=code-server}"
PORT=8080

while getopts "n:t:s:k:h" opt; do
  case $opt in
    n) NAME=$OPTARG ;;
    t) TTL=$OPTARG ;;
    s) SIZE=$OPTARG ;;
    k) KIT=$OPTARG ;;
    h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

command -v sbx >/dev/null || { echo "sbx not found. Install: https://docs.docker.com/ai/sandboxes/get-started/" >&2; exit 1; }

echo "==> Checking cloud sandbox access"
if ! existing=$(sbx --cloud ls -q 2>&1); then
  echo "$existing" >&2
  echo "Run 'sbx login' and try again." >&2
  exit 1
fi
if grep -qx "$NAME" <<<"$existing"; then
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
