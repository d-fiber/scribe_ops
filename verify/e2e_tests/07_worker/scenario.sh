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

SCENARIO=07_worker
WORKER=1
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the stack with the worker profile the command asked for"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile worker up -d --build --scale api=1 db redis nats kong api worker >/dev/null 2>&1 \
  || fail "up refused the worker profile."

for service in db redis nats kong api worker; do
  wait_for "$service is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

endpoint=$(inspect_of api '{{range .Config.Env}}{{println .}}{{end}}' | grep '^WORKER_ENDPOINT=' | cut -d= -f2-)
[ -n "$endpoint" ] || fail "the api was started without the address of the worker."
say "the api was given $endpoint"

case "$endpoint" in
  *worker*) ;;
  *) fail "the address the api got does not name the worker: $endpoint" ;;
esac
say "the address names the worker container, so the api will not call itself"

answers "a node served through the worker" 200 http://kong:8000/v1/example/items
say "a request answered while the project code ran in another container"

say "green"
