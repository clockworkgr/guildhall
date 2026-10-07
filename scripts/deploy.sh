#!/usr/bin/env bash
# Deploys the Guildhall packages and realms, in dependency order, without
# test files. Defaults target the Onyx testnet; override with env vars:
#
#   KEY=mainclock CHAIN_ID=onyx-1 REMOTE=https://rpc.onyx.testnets.gno.land:443 scripts/deploy.sh
#
# Packages that already exist on chain are skipped, so the script can be
# rerun after a failure. The key must be the one whose address is in the
# package paths (g1lnky...).
set -euo pipefail

KEY=${KEY:-mainclock}
CHAIN_ID=${CHAIN_ID:-onyx-1}
REMOTE=${REMOTE:-https://rpc.onyx.testnets.gno.land:443}
GAS_WANTED=${GAS_WANTED:-80000000}
GAS_FEE=${GAS_FEE:-100000ugnot}
MAX_DEPOSIT=${MAX_DEPOSIT:-100000000ugnot}

A=g1lnkytfqcjwllws63gvf0mv9yt04aswy4y9amhm
PKGS=(
  p/$A/guildhall/jsonw/v0
  p/$A/guildhall/trust/v0
  p/$A/guildhall/bounty/v0
  r/$A/guildhall/reputation
  r/$A/guildhall/bounties
  r/$A/guildhall/govdao
  r/$A/guildhall
)

root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

exists() {
  local data
  data=$(printf %s "gno.land/$1" | base64)
  curl -s "${REMOTE}/abci_query?path=%22vm/qfile%22&data=%22${data}%22" | grep -q '"Error": null'
}

read -rsp "Password for key ${KEY}: " PASSWORD
echo

for p in "${PKGS[@]}"; do
  if exists "$p"; then
    echo "skip   gno.land/$p (already deployed)"
    continue
  fi
  dir="$stage/$p"
  mkdir -p "$dir"
  find "$root/gno.land/$p" -maxdepth 1 -type f \( -name '*.gno' -o -name gnomod.toml \) \
    ! -name '*_test.gno' ! -name '*_filetest.gno' -exec cp {} "$dir/" \;
  echo "deploy gno.land/$p"
  printf '%s\n' "$PASSWORD" | (cd "$root" && go tool gnokey maketx addpkg \
    -pkgdir "$dir" -pkgpath "gno.land/$p" \
    -gas-wanted "$GAS_WANTED" -gas-fee "$GAS_FEE" -max-deposit "$MAX_DEPOSIT" \
    -broadcast -chainid "$CHAIN_ID" -remote "$REMOTE" \
    -insecure-password-stdin "$KEY")
done

echo "Done: ${REMOTE%%:443} / chain ${CHAIN_ID}"
