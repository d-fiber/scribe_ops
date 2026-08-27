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

SCENARIO=01_database
# shellcheck source=../support/stack.sh
. "$(dirname "$0")/../support/stack.sh"

prepare_stack
trap teardown EXIT

say "building and starting the database, this pulls 3 GB the first time"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db >/dev/null 2>&1 || fail "up refused: $(state_of db)"

wait_for "the probe says healthy" 180 healthy db \
  || fail "db never turned healthy, it is $(state_of db)"

query() {
  # shellcheck disable=SC2086
  docker compose $COMPOSE exec -T db psql -U postgres -tAc "$1" 2>/dev/null | tr -d '[:space:]'
}

say "the cluster answers as postgres, not only on its port"
[ "$(query 'select 1')" = "1" ] || fail "the probe said healthy and no session can open: the probe measures the port, not the provisioning"

roles=$(query "select count(*) from pg_roles")
[ "${roles:-0}" -ge 20 ] || fail "the cluster carries $roles roles, so initdb never ran its scripts"
say "$roles roles"

for role in authenticator pgbouncer supabase_auth_admin supabase_storage_admin; do
  [ "$(query "select 1 from pg_roles where rolname = '$role'")" = "1" ] || fail "the role $role is missing"
done
say "every role a service logs in as exists"

schemas=$(query "select count(*) from pg_namespace where nspname in ('auth','storage','realtime','extensions')")
[ "$schemas" = "4" ] || fail "only $schemas of the four schemas the images need are there"
say "the four schemas the images need are there"

password=$(awk -F= '$1 == "AUTHENTICATOR_PASSWORD" { print $2 }' "$WORK/.env")
# shellcheck disable=SC2086
docker compose $COMPOSE exec -T -e PGPASSWORD="$password" db psql -U authenticator -h 127.0.0.1 -d postgres -tAc 'select 1' >/dev/null 2>&1 \
  || fail "authenticator cannot log in with the password roles.sql gave it"
say "authenticator logs in with its own password"

# shellcheck disable=SC2086
if docker compose $COMPOSE logs db 2>&1 | grep -q 'role "postgres" does not exist'; then
  fail "the cluster is up and empty: initdb failed and restart hid it behind a healthy probe"
fi
say "no cluster started on a half-written data directory"

laid=$(query_db "select count(*) from information_schema.tables where table_name = '__trigger_events__'")
[ "$laid" = "1" ] || fail "the init script left no schema behind, so no package ever laid one down."
say "the init script ran and foundation laid its schema down"

say "green"
