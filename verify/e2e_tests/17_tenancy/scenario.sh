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

SCENARIO=17_tenancy
FIXTURE=minimal
. "$(dirname "$0")/../support/stack.sh"

prepare_stack
FIRST_PROJECT=tenant_one
FIRST_COMPOSE=$(echo "$COMPOSE" | sed "s|-p $PROJECT|-p $FIRST_PROJECT|")
FIRST_WORK=$WORK

FIXTURE=every-package
prepare_stack
SECOND_PROJECT=tenant_two
SECOND_COMPOSE=$(echo "$COMPOSE" | sed "s|-p $PROJECT|-p $SECOND_PROJECT|")
SECOND_WORK=$WORK

both_down() {
  # shellcheck disable=SC2086
  docker compose $FIRST_COMPOSE --profile '*' down --volumes --remove-orphans >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  docker compose $SECOND_COMPOSE --profile '*' down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap both_down EXIT

say "starting two projects of two different tenants"
# shellcheck disable=SC2086
docker compose $FIRST_COMPOSE up -d --build db api kong >/dev/null 2>&1 \
  || fail "the first project did not start."
# shellcheck disable=SC2086
docker compose $SECOND_COMPOSE up -d --build db api kong >/dev/null 2>&1 \
  || fail "the second project did not start."

for tenant in "$FIRST_PROJECT|$FIRST_COMPOSE" "$SECOND_PROJECT|$SECOND_COMPOSE"; do
  name=${tenant%%|*}
  compose=${tenant#*|}
  for service in db api kong; do
    # shellcheck disable=SC2086
    wait_for "$service of $name is healthy" 600 \
      sh -c "[ \"\$(docker compose $compose ps $service --format '{{.Health}}' 2>/dev/null | head -1)\" = healthy ]" \
      || fail "$service of $name never turned healthy."
  done
done

from_first() {
  docker run --rm --network "${FIRST_PROJECT}_app" "$CURL_IMAGE" \
    -s -o /dev/null -w '%{http_code}' --max-time 6 "$@" 2>/dev/null
}

second_db=$(docker inspect "$(container_of "$SECOND_PROJECT" db)" \
  --format "{{with index .NetworkSettings.Networks \"${SECOND_PROJECT}_data\"}}{{.IPAddress}}{{end}}")
second_kong=$(docker inspect "$(container_of "$SECOND_PROJECT" kong)" \
  --format "{{with index .NetworkSettings.Networks \"${SECOND_PROJECT}_app\"}}{{.IPAddress}}{{end}}")
[ -n "$second_db" ] && [ -n "$second_kong" ] || fail "the second project has no address to try."

[ "$(from_first "http://db:5432/")" = 000 ] \
  || fail "a tenant resolves the other tenant's cluster by name."
say "a tenant does not resolve the other tenant's service names"

[ "$(from_first "http://$second_db:5432/")" = 000 ] \
  || fail "a tenant reaches the other tenant's cluster at $second_db."
[ "$(from_first "http://$second_kong:8000/")" = 000 ] \
  || fail "a tenant reaches the other tenant's gateway at $second_kong."
say "a tenant does not reach the other tenant's addresses either, so the networks hold"

first_key=$(grep '^SERVICE_KEY=' "$FIRST_WORK/.env" | cut -d= -f2-)
second_key=$(grep '^SERVICE_KEY=' "$SECOND_WORK/.env" | cut -d= -f2-)
[ -n "$first_key" ] && [ -n "$second_key" ] || fail "a project names no service key."
[ "$first_key" != "$second_key" ] || fail "both tenants were given the same service key."
say "the two tenants hold different keys, so one cannot answer for the other"

socket=$(docker exec "$(container_of "$FIRST_PROJECT" api)" \
  sh -c '[ -S /var/run/docker.sock ] && echo yes || echo no' 2>/dev/null)
[ "$socket" = no ] || fail "a tenant's api can see the docker socket."
say "a tenant's api holds no docker socket, so it drives no container but its own"

volumes=$(docker volume ls --format '{{.Name}}' | grep -c "^${FIRST_PROJECT}_")
shared=$(docker volume ls --format '{{.Name}}' | grep "^${FIRST_PROJECT}_" \
  | while IFS= read -r name; do
      docker ps -a --filter "volume=$name" --format '{{.Label "com.docker.compose.project"}}' | sort -u
    done | sort -u | tr '\n' ' ')
[ "$volumes" -gt 0 ] || fail "the first project holds no volume to check."
[ "$(echo "$shared" | xargs)" = "$FIRST_PROJECT" ] \
  || fail "the first project's volumes are also held by: $shared"
say "no volume of a tenant is mounted by another tenant's container"

say "green"