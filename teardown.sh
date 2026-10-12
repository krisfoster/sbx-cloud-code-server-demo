#!/usr/bin/env bash
#
# Delete the demo cloud sandbox.   ./teardown.sh [-n NAME]
#
set -euo pipefail

NAME="${SBX_DEMO_NAME:-code-server-demo}"
while getopts "n:h" opt; do
  case $opt in
    n) NAME=$OPTARG ;;
    h) echo "Usage: ./teardown.sh [-n NAME]"; exit 0 ;;
    *) exit 2 ;;
  esac
done

sbx --cloud rm "$NAME"
