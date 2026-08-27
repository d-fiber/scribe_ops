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

SCENARIO=12_two_projects
. "$(dirname "$0")/../support/stack.sh"

prepare_stack
FIRST_COMPOSE=$(echo "$COMPOSE" | sed "s|-p $PROJECT|-p fixture|")
FIRST_HOST=fixture.scribe.localhost

FIXTURE=every-package
prepare_stack
SECOND_COMPOSE=$(echo "$COMPOSE" | sed "s|-p $PROJECT|-p fixture_full|")
SECOND_HOST=fixture_full.scribe.localhost

both_down() {
  # shellcheck disable=SC2086
  docker compose $FIRST_COMPOSE down --volumes --remove-orphans >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  docker compose $SECOND_COMPOSE down --volumes --remove-orphans >/dev/null 2>&1 || true
  docker compose -p scribe_router -f "$OPS/router/docker-compose.yaml" down >/dev/null 2>&1 || true
}
trap both_down EXIT

say "starting the one router this machine has"
docker compose -p scribe_router -f "$OPS/router/docker-compose.yaml" up -d >/dev/null 2>&1 \
  || fail "the router did not start."
wait_for "the router is healthy" 90 \
  sh -c "[ \"\$(docker compose -p scribe_router -f $OPS/router/docker-compose.yaml ps router --format '{{.Health}}')\" = healthy ]" \
  || fail "the router never turned healthy."

for pair in "$FIRST_COMPOSE|fixture" "$SECOND_COMPOSE|fixture_full"; do
  compose=${pair%|*}
  name=${pair#*|}
  # shellcheck disable=SC2086
  docker compose $compose up -d --build --no-deps kong caddy >/dev/null 2>&1 \
    || fail "$name could not start its gateway and proxy."
  docker network connect "${name}_edge" scribe_router-router-1 >/dev/null 2>&1 || true
done
say "the two projects are up, and neither publishes a port"

published=$(docker ps --filter "label=com.docker.compose.project=fixture" --format '{{.Ports}}' | grep -c '0.0.0.0' || true)
[ "$published" = "0" ] || fail "a project still publishes a host port, so a second one would collide."
say "no project holds a host port of its own"

for host in "$FIRST_HOST" "$SECOND_HOST"; do
  answered=$(http_code_on_host "$host" /v1/internal/)
  [ "$answered" = "404" ] || fail "$host answered $answered, the router did not reach its gateway."
  say "$host reaches its own gateway"
done

unknown=$(http_code_on_host nothing.scribe.localhost /)
[ "$unknown" = "404" ] || fail "an unclaimed hostname answered $unknown instead of 404."
say "a hostname no project claims is refused by the router"

say "green"
