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

SCENARIO=13_backup
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the cluster the backup reads from"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db >/dev/null 2>&1 || fail "up refused db."
wait_for "the cluster is healthy" 300 healthy db || fail "db never turned healthy, it is $(state_of db)"

query_db "create table if not exists public.kept (id int primary key, name text)" >/dev/null
query_db "insert into public.kept values (1, 'one'), (2, 'two'), (3, 'three') on conflict do nothing" >/dev/null
before=$(query_db "select count(*) from public.kept")
[ "$before" = "3" ] || fail "the rows to be backed up are not there, count is '$before'."
say "three rows are in the cluster before the backup"

say "taking a dump"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile backup run --rm --build db-backup /backups/probe.dump >/tmp/dump.log 2>&1 \
  || fail "the backup failed: $(tail -3 /tmp/dump.log)"
grep -q "\[backup\] wrote" /tmp/dump.log || fail "the backup wrote nothing it will admit to."
say "$(grep '\[backup\] wrote' /tmp/dump.log | tail -1)"

query_db "drop table public.kept" >/dev/null
gone=$(query_db "select count(*) from information_schema.tables where table_name = 'kept'")
[ "$gone" = "0" ] || fail "the table is still there, the loss this scenario recovers from never happened."
say "the table is dropped, which is the loss to recover from"

say "restoring from the dump"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile backup run --rm --entrypoint scribe-restore db-backup /backups/probe.dump \
  >/tmp/restore.log 2>&1 || fail "the restore failed: $(tail -3 /tmp/restore.log)"

after=$(query_db "select count(*) from public.kept")
[ "$after" = "3" ] || fail "the restore brought back '$after' rows instead of three."
say "the three rows are back, read from the cluster and not from the dump"

names=$(query_db "select string_agg(name, ',' order by id) from public.kept")
[ "$names" = "one,two,three" ] || fail "the rows came back changed: '$names'."
say "green"
