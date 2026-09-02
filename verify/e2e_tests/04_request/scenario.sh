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

SCENARIO=04_request
WORKER=1
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the stack the request has to cross, worker included and one api"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile worker up -d --build --scale api=1 >/dev/null 2>&1 \
  || fail "up refused the stack."

for service in db kong api worker; do
  wait_for "$service is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

table=$(query_db "select count(*) from public.items")
[ "$table" = "1" ] || fail "the sql the project ships was not replayed, items holds '$table' rows."
say "the sql the project ships was replayed into the cluster"

answers "the collection of a public node" 200 http://kong:8000/v1/example/items

body=$(http_body http://kong:8000/v1/example/items)
case "$body" in
  *'"items"'*'rendered by the fixture'*) ;;
  *) fail "the node answered without the row the fixture inserted: $body" ;;
esac
say "the answer carries the row the project inserted, so the whole path is live"

refused=$(http_body -X POST -H 'content-type: application/json' \
  -d '{"name":"written by the scenario"}' http://kong:8000/v1/example/items)
case "$refused" in
  *not_permitted*) ;;
  *) fail "an anonymous caller was allowed to write, the declared permission does nothing: $refused" ;;
esac
say "a write is refused: the permission the endpoint declares is enforced on the path"

rows=$(query_db "select count(*) from public.items where name = 'written by the scenario'")
[ "$rows" = "0" ] || fail "the write was refused and the row is in the cluster anyway."
say "nothing reached the cluster behind the refusal"

say "green"
