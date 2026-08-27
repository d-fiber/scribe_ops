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

SCENARIO=09_limits
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "starting the two services the sizing gives different budgets"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build redis db >/dev/null 2>&1 || fail "up refused the two services."
for service in redis db; do
  wait_for "$service is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy, it is $(state_of $service)"
done

host=$(docker info --format '{{.MemTotal}}')

for service in redis db; do
  limit=$(inspect_of "$service" '{{.HostConfig.Memory}}')
  [ "$limit" -gt 0 ] || fail "$service carries no memory limit, so nothing bounds it."
  [ "$limit" -lt "$host" ] || fail "$service is bounded at the whole machine, which bounds nothing."
  say "$service is bounded at $((limit / 1024 / 1024)) Mi"

  swap=$(inspect_of "$service" '{{.HostConfig.MemorySwap}}')
  [ "$swap" = "$limit" ] \
    || fail "$service may spend $((swap / 1024 / 1024)) Mi with swap, so the ceiling is not one."

  shares=$(inspect_of "$service" '{{.HostConfig.CpuShares}}')
  [ "$shares" -gt 0 ] || fail "$service carries no cpu weight, so the sizing decided nothing for it."
done
say "neither service can spend past its ceiling by swapping"

cache=$(inspect_of redis '{{.HostConfig.Memory}}')
cluster=$(inspect_of db '{{.HostConfig.Memory}}')
[ "$cache" != "$cluster" ] \
  || fail "the cache and the cluster were given the same budget, so the weights are not read."
say "the cache and the cluster were given different budgets, so the weights are read"

say "green"
