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

OPS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FRAMEWORK=${FRAMEWORK:-$OPS/../scribe}
TOOLS=${TOOLS:-$OPS/../scribe_tools}
OUT=$OPS/.e2e
FIXTURE=${FIXTURE:-minimal}

say() { echo "[$SCENARIO] $1"; }

fail() {
  echo "[$SCENARIO] $1" >&2
  if [ -n "${COMPOSE:-}" ]; then
    echo "" >&2
    # shellcheck disable=SC2086
    docker compose $COMPOSE ps --all --format 'table {{.Service}}\t{{.State}}\t{{.Health}}' 2>/dev/null | sed 's/^/  /' >&2
    for service in $(docker compose $COMPOSE ps --all --services 2>/dev/null); do
      echo "" >&2
      echo "  --- $service" >&2
      # shellcheck disable=SC2086
      docker compose $COMPOSE logs --tail 20 --no-log-prefix "$service" 2>&1 | sed 's/^/    /' >&2
    done
  fi
  exit 1
}

stale_cli() {
  [ -x "$TOOLS/out/scribe" ] || return 0
  [ -n "$(find "$OPS/services" "$OPS/env" "$OPS/stack.yaml" "$TOOLS/lib" "$TOOLS/bin" \
    -type f -newer "$TOOLS/out/scribe" -print -quit)" ]
}

build_cli() {
  say "building the CLI against the current templates"
  rm -rf "$TOOLS/templates/ops"
  for file in $(cd "$OPS" && find services env stack.yaml -type f | sort); do
    mkdir -p "$TOOLS/templates/ops/$(dirname "$file")"
    cp "$OPS/$file" "$TOOLS/templates/ops/$file.tmpl"
  done
  ( cd "$TOOLS" && dart pub get >/dev/null && mkdir -p out && dart compile exe bin/scribe.dart -o out/scribe >/dev/null )
  rm -rf "$TOOLS/out/templates" && cp -R "$TOOLS/templates" "$TOOLS/out/templates"
}

prepare_stack() {
  WORK=$OUT/$FIXTURE
  stale_cli && build_cli

  mkdir -p "$OUT"
  rm -rf "$WORK"
  cp -R "$OPS/fixtures/$FIXTURE" "$WORK"
  ln -sfn "$FRAMEWORK" "$WORK/scribe"

  STACK=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" run --dry-run | awk '/^Assembled /{ print $NF }' )
  [ -n "$STACK" ] || fail "the CLI wrote no stack."

  PROJECT="e2e-$SCENARIO"
  COMPOSE="--project-directory $WORK -p $PROJECT"
  for document in "$STACK"/*.yaml; do COMPOSE="$COMPOSE -f $document"; done
}

CURL_IMAGE=curlimages/curl:8.11.1

http_code() {
  docker run --rm --network "${PROJECT}_default" "$CURL_IMAGE" \
    -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" 2>/dev/null
}

http_body() {
  docker run --rm --network "${PROJECT}_default" "$CURL_IMAGE" \
    -s --max-time 10 "$@" 2>/dev/null
}

answers() {
  label=$1
  expected=$2
  shift 2
  got=$(http_code "$@")
  [ "$got" = "$expected" ] || fail "$label: expected $expected, got $got"
  say "$label answers $expected"
}

teardown() {
  # shellcheck disable=SC2086
  docker compose $COMPOSE --profile worker --profile functions down --volumes --remove-orphans >/dev/null 2>&1 || true
}

wait_for() {
  label=$1; timeout=$2; shift 2
  waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if "$@" >/dev/null 2>&1; then
      say "$label after ${waited}s"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done

  return 1
}

state_of() {
  # shellcheck disable=SC2086
  docker compose $COMPOSE ps --all --format '{{.Service}} {{.State}} {{.Health}}' 2>/dev/null \
    | awk -v s="$1" '$1 == s { print $2 (($3 == "" || $3 == "<nil>") ? "" : " (" $3 ")") }' \
    | head -1
}

healthy() {
  # shellcheck disable=SC2086
  [ "$(docker compose $COMPOSE ps "$1" --format '{{.Health}}' 2>/dev/null | head -1)" = healthy ]
}
