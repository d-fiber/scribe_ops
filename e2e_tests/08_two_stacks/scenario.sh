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

SCENARIO=08_two_stacks
. "$(dirname "$0")/../support/stack.sh"

SECOND=e2e-08_two_stacks-second

second_teardown() {
  # shellcheck disable=SC2086
  docker compose $SECOND_COMPOSE down --volumes --remove-orphans >/dev/null 2>&1 || true
  teardown
}

prepare_stack
SECOND_COMPOSE=$(echo "$COMPOSE" | sed "s|-p $PROJECT|-p $SECOND|")
trap second_teardown EXIT

say "starting the same project twice, under two compose names"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db redis >/dev/null 2>&1 || fail "the first stack refused to start."
# shellcheck disable=SC2086
docker compose $SECOND_COMPOSE up -d --build db redis >/dev/null 2>&1 \
  || fail "the second stack refused to start beside the first."

for service in db redis; do
  wait_for "$service of the first stack is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

first_db=$(container_of "$PROJECT" db)
second_db=$(container_of "$SECOND" db)
[ -n "$first_db" ] && [ -n "$second_db" ] || fail "one of the two stacks has no database container."
[ "$first_db" != "$second_db" ] || fail "both stacks answer with the same container, they share it."
say "each stack has its own database container"

volumes=$(docker volume ls --format '{{.Name}}' | grep -c "^${SECOND}_" || true)
[ "$volumes" -gt 0 ] || fail "the second stack created no volume of its own, it borrowed the first's."
say "each stack has its own volumes"

say "green"
