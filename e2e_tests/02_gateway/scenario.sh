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

SCENARIO=02_gateway
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the gateway alone, its upstream stays down on purpose"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d kong >/dev/null

wait_for "the gateway is healthy" 90 healthy kong \
  || fail "kong never turned healthy, it is $(state_of kong)"

answers "a public node" 503 http://kong:8000/v1/example/items
answers "a node the project keeps inward" 404 http://kong:8000/v1/internal/
answers "a path no node declares" 404 http://kong:8000/v1/nothing-here/

answers "a keyed node with no key" 401 http://kong:8000/v1/guarded/
answers "a keyed node with its own key" 503 \
  -H "x-guarded-key: $(grep '^GUARDED_KEYS=' "$WORK/.env" | cut -d= -f2)" \
  http://kong:8000/v1/guarded/
answers "a keyed node with the key of another consumer" 403 \
  -H "x-guarded-key: $(grep '^ANON_KEY=' "$WORK/.env" | cut -d= -f2)" \
  http://kong:8000/v1/guarded/
answers "a keyed node with its key in the query" 401 \
  "http://kong:8000/v1/guarded/?x-guarded-key=$(grep '^GUARDED_KEYS=' "$WORK/.env" | cut -d= -f2)"

say "green"
