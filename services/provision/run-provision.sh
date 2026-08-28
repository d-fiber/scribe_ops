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

HOST=$1
PORT=$2
USER=$3
DATABASE=$4

run() {
  psql -v ON_ERROR_STOP=1 -q -h "$HOST" -p "$PORT" -U "$USER" -d "$DATABASE" "$@"
}

echo "[provision] waiting for $HOST:$PORT"
waited=0
until pg_isready -h "$HOST" -p "$PORT" -U "$USER" -d "$DATABASE" >/dev/null 2>&1; do
  if [ "$waited" -ge 300 ]; then
    echo "[provision] $HOST:$PORT never answered, after ${waited}s of asking." >&2
    echo "[provision] Nothing was played, so the database is as it was." >&2
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done

run -c 'CREATE TABLE IF NOT EXISTS scribe_provisioning (file text PRIMARY KEY, ran_at timestamptz NOT NULL DEFAULT now())'

already() {
  [ "$(run -tAc "SELECT count(*) FROM scribe_provisioning WHERE file = '$1'")" != "0" ]
}

play() {
  [ -e "$1" ] || return 0
  find "$1" -name '*.sql' | sort | while IFS= read -r file; do
    name=${file#/provision/}
    if already "$name"; then
      echo "[provision] $name, already run"
      continue
    fi
    echo "[provision] running $name"
    run -f "$file"
    run -c "INSERT INTO scribe_provisioning (file) VALUES ('$name')"
  done
}

play /provision/setup
play /provision/foundation
play /provision/modules
play /provision/project

echo "[provision] the database carries the roles and the schema the stack expects"
