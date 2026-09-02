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

set -eu

SCOPE="recipes"

say() { echo "[$SCOPE] $1"; }
fail() { echo "[$SCOPE] $1" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")/.." && pwd)
OPS=$(cd "$HERE/.." && pwd)
FRAMEWORK=${FRAMEWORK:-$OPS/../scribe}
OUT=$HERE/.rendered/tofu

command -v tofu >/dev/null || fail "OpenTofu is not installed. Run scribe doctor."

TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}
export TF_PLUGIN_CACHE_DIR
mkdir -p "$TF_PLUGIN_CACHE_DIR"

judge() {
  named=$1
  room=$2
  recipe=$3

  mkdir -p "$room"
  python3 "$HERE/tool/fill.py" "$recipe" > "$room/main.tf.json"

  (cd "$room" && tofu init -backend=false -input=false >/dev/null && tofu validate >/dev/null) ||
    fail "OpenTofu refuses $named. Run tofu validate in $room to read why."

  say "  $named is valid, and its params.json says what a project writes"
}

say "every recipe OpenTofu applies is one it accepts"

for recipe in "$OPS"/recipes/*/*.tf.json; do
  judge "$(basename "$(dirname "$recipe")")/$(basename "$recipe")" \
    "$OUT/$(basename "$(dirname "$recipe")")-$(basename "$recipe" .tf.json)" \
    "$recipe"
done

if [ -d "$FRAMEWORK/packages" ]; then
  for recipe in "$FRAMEWORK"/packages/*/deploy/recipes/*/*.tf.json; do
    [ -e "$recipe" ] || continue
    package=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$recipe")")")")")
    type=$(basename "$(dirname "$recipe")")
    judge "$package/$type/$(basename "$recipe")" \
      "$OUT/$package-$type-$(basename "$recipe" .tf.json)" \
      "$recipe"
  done
else
  say "no framework checkout at $FRAMEWORK, so no package recipe was judged"
fi

say "every recipe a provider would apply is one it accepts."
