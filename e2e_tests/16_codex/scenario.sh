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

SCENARIO=16_codex
FIXTURE=every-package
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the cluster, the gateway and the api that answers the gauges"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db kong api rest >/dev/null 2>&1 \
  || fail "up refused the services the dashboard reads through."

for service in db kong api; do
  wait_for "$service is healthy" 600 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

dashboard=$(grep '^dashboard:' "$WORK/config.yaml" | sed 's/.*"\(.*\)".*/\1/' | sed 's|https\{0,1\}://||')
[ -n "$dashboard" ] || fail "the fixture names no dashboard, so nothing decides who may read the gauges."

service_key=$(grep '^SERVICE_KEY=' "$WORK/.env" | cut -d= -f2-)
anon=$(grep '^ANON_KEY=' "$WORK/.env" | cut -d= -f2-)

answers "the gauges straight from the api, with nothing to prove a role" 401 \
  "http://api:3000/_codex/metrics"
say "the host answers the surface only to a proved caller, gateway or not"

answers "the gauges on the public domain" 404 \
  -H "apikey: $service_key" "http://kong:8000/_codex/metrics"
say "the public domain does not carry the surface at all, so it cannot be probed there"

answers "the gauges on the dashboard domain with no key" 401 \
  -H "Host: $dashboard" "http://kong:8000/_codex/metrics"

answers "the gauges on the dashboard domain with a key that is not admin" 403 \
  -H "Host: $dashboard" -H "apikey: $anon" "http://kong:8000/_codex/metrics"

answers "writing to the gauges" 404 \
  -X POST -H "Host: $dashboard" -H "apikey: $service_key" "http://kong:8000/_codex/metrics"

gauges=$(http_body -H "Host: $dashboard" -H "apikey: $service_key" \
  "http://kong:8000/_codex/metrics")
for gauge in uptimeSeconds inflightBodyBytes residentBytes queues; do
  case "$gauges" in
    *"\"$gauge\""*) ;;
    *) fail "the gauges do not carry $gauge: $gauges" ;;
  esac
done
say "the dashboard domain with an admin key reads the four gauges"

answers "a path the surface does not serve" 404 \
  -H "Host: $dashboard" -H "apikey: $service_key" "http://kong:8000/_codex/nothing-here"

say "green"
