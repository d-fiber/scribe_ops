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

SCOPE="verify"

say() { echo "[$SCOPE] $1"; }
fail() { echo "[$SCOPE] $1" >&2; exit 1; }

OPS=$(cd "$(dirname "$0")/.." && pwd)
FRAMEWORK=${FRAMEWORK:-$OPS/../scribe}
TOOLS=${TOOLS:-$OPS/../scribe_tools}
OUT=$OPS/.rendered

[ -d "$FRAMEWORK" ] || fail "No framework checkout at $FRAMEWORK. Set FRAMEWORK to one."
[ -d "$TOOLS" ] || fail "No CLI checkout at $TOOLS. Set TOOLS to one."

say "laying the templates into the CLI, adding the suffix back"
rm -rf "$TOOLS/templates/ops"
for file in $(cd "$OPS" && find services env stack.yaml -type f | sort); do
  mkdir -p "$TOOLS/templates/ops/$(dirname "$file")"
  cp "$OPS/$file" "$TOOLS/templates/ops/$file.tmpl"
done

say "building the CLI that renders them"
( cd "$TOOLS" && dart pub get >/dev/null && mkdir -p out && dart compile exe bin/scribe.dart -o out/scribe >/dev/null )
rm -rf "$TOOLS/out/templates"
cp -R "$TOOLS/templates" "$TOOLS/out/templates"

rm -rf "$OUT"
mkdir -p "$OUT"

for fixture in $(cd "$OPS/fixtures" && ls); do
  say "rendering $fixture"
  work=$OUT/$fixture
  cp -R "$OPS/fixtures/$fixture" "$work"
  ln -sfn "$FRAMEWORK" "$work/scribe"

  if ! ( cd "$work" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" run --dry-run ) > "$OUT/$fixture.log" 2>&1; then
    cat "$OUT/$fixture.log"
    fail "$fixture: the CLI refused to render."
  fi

  stack=$(awk '/^Assembled /{ print $NF }' "$OUT/$fixture.log")
  if [ -z "$stack" ]; then
    cat "$OUT/$fixture.log"
    fail "$fixture: the CLI wrote no stack."
  fi

  say "$fixture: the compose holds together"
  compose_files=""
  for document in "$stack"/*.yaml; do compose_files="$compose_files -f $document"; done
  # shellcheck disable=SC2086
  docker compose --project-directory "$work" -p "scribe-ops-$fixture" $compose_files config --quiet 2>/dev/null ||
    fail "$fixture: docker compose refuses the rendered stack."

  say "$fixture: the gateway is a document Kong reads"
  python3 - "$stack/services/gateway/kong.yml" <<'PY'
import sys, yaml
document = yaml.safe_load(open(sys.argv[1]).read())
for key in ("_format_version", "services", "consumers", "acls", "upstreams"):
    assert key in document, f"kong.yml carries no {key}"
paths = [path for service in document["services"] for route in service["routes"] for path in route["paths"]]
assert len(paths) == len(set(paths)), f"two routes answer the same path: {paths}"
PY

  say "$fixture: the proxy is a Caddyfile Caddy adapts"
  docker run --rm -e API_DOMAIN=https://fixture.example.com -v "$stack/services/proxy/Caddyfile:/f:ro" caddy:2 \
    caddy validate --config /f --adapter caddyfile >/dev/null 2>&1 ||
    fail "$fixture: caddy refuses the rendered Caddyfile."

  if ! docker run --rm -v "$stack/services/proxy/Caddyfile:/f:ro" caddy:2 caddy fmt --diff /f >/dev/null 2>&1; then
    docker run --rm -v "$stack/services/proxy/Caddyfile:/f:ro" caddy:2 caddy fmt --diff /f 2>/dev/null | grep -E '^[-+]'
    fail "$fixture: the rendered Caddyfile is not what caddy fmt writes."
  fi

  say "$fixture: every environment file a service reads was written"
  for audience in $(cd "$OPS/env" && ls); do
    [ -f "$stack/env/$audience" ] || fail "$fixture: $audience was not written."
  done
  python3 - "$stack" <<'PY'
import pathlib, sys, yaml
stack = pathlib.Path(sys.argv[1])
written = {p.name for p in (stack / "env").iterdir()}
document = yaml.safe_load((stack / "docker-compose.yaml").read_text())
missing = {}
for name, service in document["services"].items():
    for entry in service.get("env_file", []):
        audience = pathlib.Path(entry["path"]).name
        if entry.get("required", True) and audience not in written:
            missing.setdefault(audience, []).append(name)
assert not missing, f"required but never written: {missing}"
PY

  say "$fixture: nothing was left unrendered"
  if grep -rlq '{{' "$stack"; then
    grep -rln '{{' "$stack"
    fail "$fixture: a placeholder survived the render."
  fi
done

say "the entrypoint is a script shellcheck accepts"
if command -v shellcheck >/dev/null; then
  shellcheck "$OPS/services/gateway/kong-entrypoint.sh" || fail "shellcheck refuses the gateway entrypoint."
else
  say "shellcheck is not installed, skipping it"
fi

say "everything a pull request has to pass is green."
