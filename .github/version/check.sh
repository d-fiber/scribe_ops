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

set -euo pipefail

SCOPE="version"

say() { echo "[$SCOPE] $1"; }
fail() { echo "[$SCOPE] $1" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

declared=$(awk '/^## [0-9]+\.[0-9]+\.[0-9]+$/ { print $2; exit }' CHANGELOG.md)

[ -n "$declared" ] || fail "CHANGELOG.md names no version. Its first numbered section is the version this repository holds."

say "the version is $declared, and CHANGELOG.md is the only place that says so"

body=$(awk -v version="$declared" '
  $0 == "## " version { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' CHANGELOG.md | tr -d '[:space:]')

[ -n "$body" ] || fail "the section for $declared is empty. A version nobody wrote about is a version nobody can read."

say "the section for it says something"

if git rev-parse "v$declared" >/dev/null 2>&1; then
  say "v$declared is already written, so this push adds to a version that is out"
else
  say "v$declared has no tag yet, so a green run on dev writes one"
fi
