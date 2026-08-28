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
SCENARIO=19_deploy
FIXTURE=minimal
# shellcheck source=../support/stack.sh
. "$(dirname "$0")/../support/stack.sh"

PROJECT=e2e_19_deploy

deployment_down() {
  ( cd "$WORK" 2>/dev/null && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" destroy --target here --data --yes ) \
    >/dev/null 2>&1 || true
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" \
    | xargs -r docker rm --force --volumes >/dev/null 2>&1 || true
}
trap deployment_down EXIT

WORK=$OUT/$FIXTURE
stale_cli && build_cli

mkdir -p "$OUT"
rm -rf "$WORK"
cp -R "$OPS/fixtures/$FIXTURE" "$WORK"
ln -sfn "$FRAMEWORK" "$WORK/scribe"
sed -i.bak "s|^name: .*|name: $PROJECT|" "$WORK/config.yaml" && rm -f "$WORK/config.yaml.bak"
rm -rf "$WORK/configuration"

say "forging the project, which is what writes the configuration it declares"
( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" forge ) >/dev/null 2>&1 \
  || fail "forge refused a project it had just been given."
[ -f "$WORK/configuration/main.yaml" ] || fail "forge wrote no configuration/main.yaml."
say "it wrote configuration/main.yaml, having been given none"

cat > "$WORK/configuration/main.yaml" <<'YAML'
targets:
  here:
    kind: dev
YAML

say "deploying it, which is the command no scenario had ever run"
deployed=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" deploy --target here 2>&1 )
status=$?
[ "$status" = 0 ] || fail "deploy left with $status:
$(echo "$deployed" | tail -20)"

echo "$deployed" | grep -q '^ready ' || fail "deploy said it was done without ever saying it was ready."
say "deploy answered ready, and only once the stack had settled"

running=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}}' | wc -l | tr -d ' ')
[ "$running" -ge 5 ] || fail "deploy said ready with $running container(s), which is not a stack."

settled=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
  --format '{{.Names}} {{.Status}}' | grep -cv 'healthy\|Exited (0)' || true)
[ "$settled" = 0 ] || fail "deploy said ready while $settled container(s) were neither healthy nor cleanly done:
$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} {{.Status}}')"
say "every container it left behind is healthy, or ran once and left with nothing to say"

migrated=$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
  --format '{{.Names}} {{.Status}}' | grep 'db-migrate' | grep -c 'Exited (0)' || true)
[ "$migrated" = 1 ] || fail "the migration did not run to completion before deploy called the stack ready:
$(docker ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} {{.Status}}')"
say "the migrations ran, and api and rest waited for them"

say "taking it down again, and asking for the data with it"
removed=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" destroy --target here --data --yes 2>&1 )
status=$?
[ "$status" = 0 ] || fail "destroy left with $status:
$(echo "$removed" | tail -20)"

left=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | wc -l | tr -d ' ')
[ "$left" = 0 ] || fail "destroy left $left container(s) behind."
volumes=$(docker volume ls -q --filter "name=${PROJECT}_" | wc -l | tr -d ' ')
[ "$volumes" = 0 ] || fail "destroy left $volumes volume(s) behind, and --data was asked for."
say "nothing of it is left, neither a container nor a volume"

say "green"
