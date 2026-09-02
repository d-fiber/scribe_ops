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

SCENARIO=11_every_package
FIXTURE=every-package
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the stack of a project that mounts every package"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build >/dev/null 2>&1 || fail "up refused the full selection."

for service in db redis nats kong api; do
  wait_for "$service is healthy" 420 healthy "$service" \
    || fail "$service never turned healthy with every package mounted, it is $(state_of $service)"
done

running=$(services_running)
for service in storage imgproxy; do
  case " $running " in
    *" $service "*) ;;
    *) fail "$service is mounted by a package and is not running: $running" ;;
  esac
done
say "the services a mounted package brings are up beside the socle"

for absent in realtime opensearch; do
  case " $running " in
    *" $absent "*) fail "$absent started without its profile being asked for." ;;
  esac
done
say "the heavy services stayed down, their profiles were not asked for"

exited=$(exit_code_of db-migrate)
[ "$exited" = "0" ] || fail "the migration container left with $exited under the full selection."
say "the migration ran through every package's schema and left with 0"

for pair in auth:__accounts__ search:__search_indices__ dynamic_links:__dynamic_links__ \
  remote_configs:__remote_configs__ audience:__audiences__; do
  pkg=${pair%%:*}
  table=${pair##*:}
  found=$(query_db "select count(*) from information_schema.tables where table_name = '$table'")
  [ "$found" = "1" ] || fail "$pkg is mounted and $table was never created."
done
say "every mounted package's schema reached the database, one table each"

say "raising the two profiles a project has to ask for, this pulls opensearch"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile realtime --profile search up -d --build >/dev/null 2>&1 \
  || fail "up refused the two heavy profiles."

for service in realtime opensearch; do
  wait_for "$service is healthy" 600 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done
say "both answer once the project asks for them"

say "green"
