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

SCENARIO=18_resources
FIXTURE=minimal
TARGET=elsewhere
# shellcheck source=../support/stack.sh
. "$(dirname "$0")/../support/stack.sh"

OUTSIDE=e2e-$SCENARIO-outside

outside_down() {
  docker rm -f "$OUTSIDE" >/dev/null 2>&1 || true
}

everything_down() {
  outside_down
  teardown
}

WORK_READY=no
prepare_outside() {
  WORK=$OUT/$FIXTURE
  stale_cli && build_cli

  mkdir -p "$OUT"
  rm -rf "$WORK"
  cp -R "$HERE/fixtures/$FIXTURE" "$WORK"
  ln -sfn "$FRAMEWORK" "$WORK/scribe"

  mkdir -p "$WORK/configuration"
  cat > "$WORK/configuration/main.yaml" <<'YAML'
targets:
  elsewhere:
    kind: machine
    machine:
      cores: 4
      threads: 8
      memory: 8g

deploy:
  elsewhere:
    postgres: external
YAML

  {
    echo "POSTGRES_HOST=$OUTSIDE"
    echo "POSTGRES_PORT=5432"
    echo "POSTGRES_DATABASE=postgres"
    # The account a recipe hands over has to be able to create a role, because
    # provisioning creates six. In this image that is supabase_admin and not
    # postgres, which the cluster marks as unable to touch a reserved role.
    echo "POSTGRES_USER=supabase_admin"
  } >> "$WORK/.env"

  WORK_READY=yes
}

prepare_outside
trap everything_down EXIT

say "rendering a stack whose database is not one of its containers"
# shellcheck disable=SC2086
STACK=$( cd "$WORK" && SCRIBE_STACK_HOME="$OUT/cache" "$TOOLS/out/scribe" run --dry-run --target "$TARGET" \
  | awk '/^Assembled /{ print $NF }' )
[ -n "$STACK" ] || fail "the CLI wrote no stack."

PROJECT="e2e-$SCENARIO"
COMPOSE="--project-directory $WORK -p $PROJECT"
for document in "$STACK"/*.yaml; do COMPOSE="$COMPOSE -f $document"; done

grep -q '^  db:' "$STACK/docker-compose.yaml" \
  && fail "db is still a service of the stack, so the placement did nothing"
say "the db service left the document"

grep -q '      db:' "$STACK/docker-compose.yaml" \
  && fail "something still waits on db, and Compose refuses a dependency it cannot see"
say "nothing waits on it any more"

grep -q '@${POSTGRES_HOST}:' "$STACK/docker-compose.yaml" \
  || fail "no consumer reads the address of a database the stack does not own"
say "the consumers read it from the environment instead"

say "starting what is left, which creates the networks"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d --no-deps nats >/dev/null 2>&1 || fail "up refused: $(state_of nats)"

say "putting a database on the data network, as somebody else's would be"
password=$(awk -F= '$1 == "POSTGRES_PASSWORD" { print $2 }' "$WORK/.env")
# The image the framework ships, because what the stack needs of a database is
# not only PostgreSQL: foundation opens pg_cron and pgcrypto, and a plain image
# refuses the first with "extension is not available". A database somewhere else
# has to carry them too, and this is where that is proven rather than assumed.
docker run -d --name "$OUTSIDE" \
  --network "${PROJECT}_data" --network-alias "$OUTSIDE" \
  -e POSTGRES_PASSWORD="$password" \
  supabase/postgres:15.8.1.085 >/dev/null 2>&1 || fail "the outside database did not start"

# Asked from the network and not from the host, and asked three times: this
# image serves a socket before it listens on a port, and restarts once while it
# initialises. A single answer is therefore not an answer, it is a window.
answers_on_the_network() {
  for _ in 1 2 3; do
    docker run --rm --network "${PROJECT}_data" postgres:15.19-alpine \
      pg_isready -h "$OUTSIDE" -p 5432 -U supabase_admin >/dev/null 2>&1 || return 1
    sleep 2
  done
}

wait_for "it answers on the network, and keeps answering" 240 answers_on_the_network \
  || fail "the outside database never answered where the stack would reach it"

say "provisioning it, which is the job that used to be the entrypoint"
# shellcheck disable=SC2086
docker compose $COMPOSE up --exit-code-from provision provision >/dev/null 2>&1 \
  || fail "provision refused: $(docker compose $COMPOSE logs provision 2>&1 | tail -20)"

ran=$(docker exec -e PGPASSWORD="$password" "$OUTSIDE" psql -U supabase_admin -d postgres -tAc \
  "select count(*) from scribe_provisioning" | tr -d '[:space:]')
[ "${ran:-0}" -ge 2 ] || fail "provision wrote down $ran files, so it never ran against this database"
say "provision wrote down the $ran files it played into it"

roles=$(docker exec -e PGPASSWORD="$password" "$OUTSIDE" psql -U supabase_admin -d postgres -tAc \
  "select count(*) from pg_roles where rolname in ('authenticator','migrator','anon','authenticated','service_role')" | tr -d '[:space:]')
[ "$roles" = "5" ] || fail "the outside database carries $roles of the five roles the stack logs in as"
say "it carries the five roles the stack logs in as"

laid=$(docker exec -e PGPASSWORD="$password" "$OUTSIDE" psql -U supabase_admin -d postgres -tAc \
  "select count(*) from information_schema.tables where table_name = '__trigger_events__'" | tr -d '[:space:]')
[ "$laid" = "1" ] || fail "no schema was laid into a database the stack does not own"
say "and the schema the framework lays down"

say "starting the rest, which logs into a database it never started"
# shellcheck disable=SC2086
docker compose $COMPOSE up -d rest >/dev/null 2>&1 || fail "rest refused: $(state_of rest)"

wait_for "rest is healthy against it" 90 healthy rest \
  || fail "rest never turned healthy, it is $(state_of rest)"

[ -z "$(container_of "$PROJECT" db)" ] || fail "a db container exists, and none should"
say "no database container was ever started"

say "green"
