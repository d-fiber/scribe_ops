#!/usr/bin/env bash
# Copyright (C) 2026 Fiber
#
# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at https://mozilla.org/MPL/2.0/.
#
# What you may do:
# - Use this software for any purpose, including commercially, and build and
#   sell your own products on top of it.
# - Change it, and create new works based on it.
# - Distribute copies of it, with or without your changes.
# - Combine it with files under any other licence, proprietary ones included,
#   and licence that larger work on your own terms.
#
# What you must do in return:
# - Keep this notice on every file you received it on.
# - Publish, under these same terms, the source of every file covered by them
#   that you distribute, including the ones you changed, so that whoever
#   receives your version can obtain that source.
# - Leave Fiber out of it: the name "Fiber", its branding, its logos and its
#   trademarks may not be used to endorse or promote what you build, and this
#   licence grants no right to them.
#
# Disclaimer:
# AS FAR AS THE LAW ALLOWS, THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY
# OR CONDITION OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR
# NON-INFRINGEMENT. IN NO EVENT SHALL FIBER BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING BUT NOT
# LIMITED TO LOSS OF USE, DATA, PROFITS, OR BUSINESS INTERRUPTION) ARISING OUT
# OF OR RELATED TO THESE TERMS OR THE USE OR NATURE OF THE SOFTWARE, UNDER ANY
# KIND OF LEGAL CLAIM.
#
# This header is a summary written for convenience. Where it differs from the
# LICENSE file, the LICENSE file governs.

SCENARIO=20_ship
FIXTURE=minimal
# shellcheck source=../support/stack.sh
. "$(dirname "$0")/../support/stack.sh"

PROJECT=e2e_20_ship
SHIP_HOST=${SHIP_HOST:-localhost}
SHIP_REGISTRY_PORT=${SHIP_REGISTRY_PORT:-5177}
REGISTRY_NAME=e2e-20-ship-registry

query_remote_db() {
  container=$(ssh "$SHIP_HOST" "docker ps -q --filter label=com.docker.compose.project=$PROJECT --filter label=com.docker.compose.service=db")
  [ -n "$container" ] || { echo ""; return 0; }
  printf '%s\n' "$1" | ssh "$SHIP_HOST" "docker exec -i $container su postgres -c 'psql -tA'" 2>/dev/null | tr -d '[:space:]'
}

WATCHDOG_PIDFILE=$(mktemp)
TUNNEL_PIDFILE=$(mktemp)

cleanup() {
  [ -f "$WATCHDOG_PIDFILE" ] && kill "$(cat "$WATCHDOG_PIDFILE")" >/dev/null 2>&1
  [ -f "$TUNNEL_PIDFILE" ] && kill "$(cat "$TUNNEL_PIDFILE")" >/dev/null 2>&1
  rm -f "$WATCHDOG_PIDFILE" "$TUNNEL_PIDFILE"
  ( cd "$WORK" 2>/dev/null && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" destroy --target there --data --yes ) \
    >/dev/null 2>&1 || true
  ssh "$SHIP_HOST" "docker rm -f $REGISTRY_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

say "starting a throwaway registry on $SHIP_HOST, reachable only from there"
ssh "$SHIP_HOST" "docker rm -f $REGISTRY_NAME >/dev/null 2>&1; docker run -d --name $REGISTRY_NAME -p 127.0.0.1:$SHIP_REGISTRY_PORT:5000 registry:2" \
  >/dev/null || fail "could not start a registry on $SHIP_HOST."

port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$SHIP_REGISTRY_PORT") 2>/dev/null && { exec 3<&-; exec 3>&-; return 0; }
  return 1
}

say "keeping the tunnel to $SHIP_HOST up for as long as this scenario runs, restarting it if it drops"
(
  while true; do
    if ! port_open; then
      if [ -f "$TUNNEL_PIDFILE" ]; then kill "$(cat "$TUNNEL_PIDFILE")" >/dev/null 2>&1 || true; fi
      ssh -N -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
        -L "$SHIP_REGISTRY_PORT:localhost:$SHIP_REGISTRY_PORT" "$SHIP_HOST" &
      echo "$!" > "$TUNNEL_PIDFILE"
    fi
    sleep 3
  done
) &
echo "$!" > "$WATCHDOG_PIDFILE"

up=0
for _ in $(seq 1 20); do
  if port_open; then
    up=1
    break
  fi
  sleep 1
done
[ "$up" = "1" ] || fail "the SSH tunnel to $SHIP_HOST's registry never came up."

WORK=$OUT/$FIXTURE
stale_cli && build_cli

mkdir -p "$OUT"
rm -rf "$WORK"
cp -R "$HERE/fixtures/$FIXTURE" "$WORK"
mkdir -p "$WORK/scribe"
for tree in alchemy engine packages protocol sdk deno.json deno.lock; do
  [ -e "$FRAMEWORK/$tree" ] && cp -RL "$FRAMEWORK/$tree" "$WORK/scribe/$tree"
done
sed -i.bak "s|^name: .*|name: $PROJECT|" "$WORK/config.yaml" && rm -f "$WORK/config.yaml.bak"
rm -rf "$WORK/configuration"

say "forging the project"
( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" forge ) >/dev/null 2>&1 \
  || fail "forge refused a project it had just been given."

cat > "$WORK/configuration/main.yaml" <<YAML
targets:
  there:
    kind: vps
    host: $SHIP_HOST
    registry: "localhost:$SHIP_REGISTRY_PORT"
YAML

say "deploying to a target that ships, no --yes: nothing here is provisioned so none should be asked"
set +e
deployed=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" deploy --target there 2>&1 )
status=$?
set -e
[ "$status" = 0 ] || fail "deploy left with $status:
$(echo "$deployed" | tail -40)"

echo "$deployed" | grep -q '^ready ' || fail "deploy said it was done without ever saying it was ready:
$(echo "$deployed" | tail -40)"
say "it shipped and answered ready"

migrated=$(ssh "$SHIP_HOST" "docker ps -a --filter label=com.docker.compose.project=$PROJECT --filter label=com.docker.compose.service=db-migrate --format '{{.Status}}'")
case "$migrated" in
  *"Exited (0)"*) ;;
  *) fail "the migration on the remote host did not exit 0, it is: $migrated" ;;
esac
say "the migration ran to completion on the remote host"

cron=$(query_remote_db "select count(*) from pg_extension where extname = 'pg_cron'")
[ "$cron" = "1" ] || fail "pg_cron is not installed on the remote database. foundation's own db/init never reached the host, which is exactly what _carryFrameworkSql exists to do."
say "foundation's own schema reached the remote host, not just the project's"

say "taking it down again, and asking for the data with it"
set +e
removed=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" destroy --target there --data --yes 2>&1 )
status=$?
set -e
[ "$status" = 0 ] || fail "destroy left with $status:
$(echo "$removed" | tail -20)"

left=$(ssh "$SHIP_HOST" "docker ps -aq --filter label=com.docker.compose.project=$PROJECT | wc -l" | tr -d '[:space:]')
[ "$left" = "0" ] || fail "destroy left $left container(s) behind on $SHIP_HOST."
say "nothing of it is left on $SHIP_HOST"

say "green"
