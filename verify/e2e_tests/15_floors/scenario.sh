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

SCENARIO=15_floors
FIXTURE=every-package
TARGET=vps
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT

stale_cli && build_cli
mkdir -p "$OUT"
rm -rf "$OUT/$FIXTURE"
cp -R "$HERE/fixtures/$FIXTURE" "$OUT/$FIXTURE"
ln -sfn "$FRAMEWORK" "$OUT/$FIXTURE/scribe"

refusal=$( cd "$OUT/$FIXTURE" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" run --dry-run --target cramped 2>&1 || true )
case "$refusal" in
  *"does not fit on 4 c / 8 t, 4 Go"*) ;;
  *) fail "a four gigabyte machine took eight packages without a word: $(echo "$refusal" | tail -1)" ;;
esac
say "the tool refuses eight packages on four gigabytes instead of assembling a stack that cannot boot"

prepare_stack

say "the stack is rendered for the target that fits, and every service has to answer on it"
# shellcheck disable=SC2086
docker compose $COMPOSE --profile realtime --profile search up -d --build >/dev/null 2>&1 \
  || fail "up refused the stack rendered for $TARGET."

for service in db kong api storage realtime opensearch; do
  wait_for "$service is healthy" 600 healthy "$service" \
    || fail "$service never turned healthy on the $TARGET budget, it is $(state_of $service)"
done

key=$(grep '^SERVICE_KEY=' "$WORK/.env" | cut -d= -f2-)
[ -n "$key" ] || fail "the fixture names no service key, so nothing can be uploaded."

written=$(http_body -X POST \
  -H "authorization: Bearer $key" \
  -H "content-type: text/plain" \
  --data-binary "written against the floor" \
  "http://storage:5000/object/public_bucket/floor.txt")
case "$written" in
  *floor.txt*) ;;
  *) fail "storage refused the write on the memory its floor gives it: $written" ;;
esac
say "storage takes a write on the memory its floor gives it"

for service in $(docker compose $COMPOSE ps --all --services 2>/dev/null | sort); do
  [ "$(inspect_of "$service" '{{.State.OOMKilled}}')" = true ] \
    && fail "$service was killed for going over the memory its floor gives it."
  restarts=$(inspect_of "$service" '{{.RestartCount}}')
  case "$restarts" in
    ""|0) ;;
    *) fail "$service restarted $restarts times, so its floor does not hold it." ;;
  esac
done
say "no service was killed, and none restarted"

say "green"
