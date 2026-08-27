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

set -e

SCENARIO=14_load
WORKER=1
FIXTURE=every-package
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the whole path a request crosses"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile worker --profile realtime --profile search up -d --build --scale api=1 >/dev/null 2>&1 \
  || fail "up refused the stack."

for service in db kong api worker opensearch realtime storage; do
  wait_for "$service is healthy" 420 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

warm=$(http_code http://kong:8000/v1/example/items)
[ "$warm" = "200" ] || fail "the path answers $warm before any load, so the run would measure nothing."
say "the path answers before the load starts"

refused=$(http_code http://kong:8000/v1/guarded/)
[ "$refused" = "401" ] \
  || fail "a call with no key answered $refused, so this run cannot tell a refusal from an answer."
say "a refusal reads as 401, so the codes this run counts mean something"

report() {
  # shellcheck disable=SC2086
  docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.MemPerc}}|{{.CPUPerc}}' \
    $(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format '{{.ID}}') 2>/dev/null \
    | sed "s|^|    |"
}

broke=""
peak=""
for concurrency in 1 2 4 8 16 32 64 128; do
  started=$(date +%s)
  # shellcheck disable=SC2046
  docker run --rm --name "$PROJECT-load" --network "${PROJECT}_app" "$CURL_IMAGE" \
    -s -w '%{http_code}\n' --max-time 20 --parallel --parallel-immediate \
    --parallel-max "$concurrency" \
    $(for _ in $(seq 1 "$concurrency"); do echo "-o /dev/null http://kong:8000/v1/example/items"; done) \
    > /tmp/load-codes.txt 2>/dev/null &
  burst=$!

  sleep 1
  during=$(report)

  wait "$burst" 2>/dev/null || true
  codes=$(sort /tmp/load-codes.txt | uniq -c | tr '\n' ' ')
  elapsed=$(( $(date +%s) - started ))

  say "$concurrency in flight in ${elapsed}s: $codes"

  served=$(echo "$codes" | grep -oE '[0-9]+ 200' | awk '{print $1}')
  [ -n "$served" ] || served=0
  [ -n "$during" ] && peak=$during
  if [ "$served" != "$concurrency" ]; then
    broke="$concurrency"
    break
  fi
done

say "what each service was holding while the load ran"
echo "$peak"

if [ -n "$broke" ]; then
  say "the first refusal came at $broke requests in flight"
else
  say "nothing was refused up to 128 in flight, the ceiling is above what this run reached"
fi

for service in db kong api worker redis nats opensearch realtime storage; do
  state=$(state_of "$service")
  case "$state" in
    running*) ;;
    *) fail "$service did not survive the load, it is $state" ;;
  esac
done
say "every service is still up after the load"

say "green"
