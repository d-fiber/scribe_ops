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

SCENARIO=03_stack
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting every service the project takes by default, this builds three images"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build >/dev/null 2>&1 || fail "up refused the stack."

for service in db redis nats kong api caddy; do
  wait_for "$service is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

exited=$(exit_code_of db-migrate)
[ "$exited" = "0" ] || fail "the migration container left with $exited, not 0."
say "the migration ran once and left with 0"

running=$(services_running)
for absent in functions worker; do
  case " $running " in
    *" $absent "*) fail "$absent started without its profile being asked for." ;;
  esac
done
say "functions and worker stayed down, their profiles were not asked for"

for service in db redis nats kong api rest caddy; do
  case " $running " in
    *" $service "*) ;;
    *) fail "$service is not running, the stack holds: $running" ;;
  esac
done
say "the seven services a default project runs are up"

say "green"
