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

SCENARIO=06_target
TARGET=vps
. "$(dirname "$0")/../support/stack.sh"

trap teardown EXIT
prepare_stack

say "the stack was rendered for the target $TARGET, not for this machine"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --build db redis nats >/dev/null 2>&1 \
  || fail "the target the project declares does not start on this machine."

for service in db redis nats; do
  wait_for "$service is healthy" 300 healthy "$service" \
    || fail "$service never turned healthy on the $TARGET budget, it is $(state_of $service)"
done

limit=$(inspect_of db '{{.HostConfig.Memory}}')
[ "$limit" -gt 0 ] || fail "the memory limit the target sizes never reached the daemon."
say "the cluster carries a memory limit of $((limit / 1024 / 1024)) Mi"

cpus=$(inspect_of db '{{.HostConfig.NanoCpus}}')
[ "$cpus" -gt 0 ] || fail "the target caps cores and the daemon sees no cpu ceiling."
say "the cluster carries a cpu ceiling of $((cpus / 100000)) hundredths of a core"

host_memory=$(docker info --format '{{.MemTotal}}')
[ "$limit" -lt "$host_memory" ] \
  || fail "the limit is the whole machine, so the target sized nothing."
say "the limit comes from the declared machine, not from the one running the test"

say "green"
