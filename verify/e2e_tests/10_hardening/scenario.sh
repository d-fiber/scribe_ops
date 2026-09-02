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

SCENARIO=10_hardening
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting every service the hardening applies to"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build api kong caddy db redis nats >/dev/null 2>&1 \
  || fail "up refused the stack."

wait_for "the api is healthy" 300 healthy api || fail "api never turned healthy, it is $(state_of api)"

for service in api kong caddy; do
  privileged=$(inspect_of "$service" '{{index .HostConfig.SecurityOpt 0}}')
  case "$privileged" in
    *no-new-privileges*) ;;
    *) fail "$service can still gain privileges, it carries '$privileged'." ;;
  esac
done
say "the three services that face the network cannot gain privileges"

for service in api kong caddy; do
  dropped=$(inspect_of "$service" '{{.HostConfig.CapDrop}}')
  case "$dropped" in
    *ALL*) ;;
    *) fail "$service keeps its capabilities, it drops '$dropped'." ;;
  esac
done
say "each of them starts with every capability dropped"

for service in api worker; do
  declared=$(grep -c '^ *user:' "$OPS/services/${service}/docker-compose.yaml" || true)
  [ "$declared" -ge 1 ] || fail "$service no longer declares the user it runs as."
done
uid=$(inspect_of api '{{.Config.User}}')
[ -n "$uid" ] && [ "$uid" != "0" ] && [ "$uid" != "root" ] \
  || fail "the api runs as root, it reports '$uid'."
say "the api runs as $uid, not as root"

floating=$(grep -h 'image:' "$OPS"/services/*/docker-compose.yaml \
  | sed 's/.*image: *//;s/"//g' | grep -v '[0-9]\.[0-9]' || true)
[ -z "$floating" ] || fail "an image is not pinned to a patch: $floating"
say "every image the socle pulls is pinned"

say "green"
