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

SCENARIO=05_restart
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the cluster a first time"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db >/dev/null 2>&1 || fail "up refused db."
wait_for "the cluster is healthy" 300 healthy db || fail "db never turned healthy, it is $(state_of db)"

query_db "insert into public.items (name) values ('survives a restart')" >/dev/null
before=$(query_db "select count(*) from public.items")
say "the cluster holds $before rows before the restart"

# shellcheck disable=SC2086
docker compose $COMPOSE stop db >/dev/null 2>&1
# shellcheck disable=SC2086
docker compose $COMPOSE up -d db >/dev/null 2>&1 || fail "the second up refused db."
wait_for "the cluster is healthy again" 300 healthy db \
  || fail "db never came back, it is $(state_of db)"

after=$(query_db "select count(*) from public.items")
[ "$after" = "$before" ] || fail "the volume lost rows across a restart: $before became $after."
say "the volume kept every row across the restart"

survivor=$(query_db "select count(*) from public.items where name = 'survives a restart'")
[ "$survivor" = "1" ] || fail "the row written before the restart is gone."
say "a row written before the restart is still there"

# shellcheck disable=SC2086
replayed=$(docker compose $COMPOSE logs db 2>/dev/null | grep -c '\[init\] running' || true)
[ "$replayed" = "0" ] && fail "the init scripts never ran, so this proves nothing about replaying them."
say "the init scripts ran once, at the first start"

roles=$(query_db "select count(*) from pg_roles")
[ "$roles" -ge 20 ] || fail "the second start lost roles, only $roles remain."
say "the roles the first start created are still there"

say "green"
