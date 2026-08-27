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

say() { echo "[provision] $1"; }

command -v apt-get >/dev/null 2>&1 || { echo "[provision] this host is not Debian or Ubuntu" >&2; exit 1; }

DART_VERSION=${DART_VERSION:-3.12.2}
DENO_VERSION=${DENO_VERSION:-2.7.14}

say "docker, from the official repository and not from snap"
if snap services docker 2>/dev/null | awk 'NR > 1 && $3 == "active" { found = 1 } END { exit !found }'; then
  echo "[provision] the snap docker is running here, and it refuses no-new-privileges." >&2
  echo "[provision] stop it first: sudo snap stop docker. Its data stays where it is," >&2
  echo "[provision] and sudo snap start docker brings it back." >&2
  exit 1
fi

if snap list docker >/dev/null 2>&1; then
  say "a snap docker is installed but stopped, its data is left untouched"
fi

if [ ! -x /usr/bin/docker ]; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg unzip
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
fi
say "docker $(/usr/bin/docker --version)"

say "the hardening this host has to accept"
if ! /usr/bin/docker run --rm --security-opt no-new-privileges:true alpine:3 echo ok >/dev/null 2>&1; then
  echo "[provision] this docker refuses no-new-privileges, and every service of the stack carries it." >&2
  exit 1
fi
say "no-new-privileges is accepted, the stack can run here"

if ! command -v dart >/dev/null 2>&1; then
  say "dart $DART_VERSION"
  curl -4 -fsSL -o /tmp/dartsdk.zip \
    "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-x64-release.zip"
  sudo rm -rf /opt/dart-sdk
  sudo unzip -qo /tmp/dartsdk.zip -d /opt
  sudo ln -sf /opt/dart-sdk/bin/dart /usr/local/bin/dart
  rm -f /tmp/dartsdk.zip
fi
say "dart $(dart --version 2>&1 | head -1)"

if ! command -v deno >/dev/null 2>&1; then
  say "deno $DENO_VERSION"
  curl -4 -fsSL -o /tmp/deno.zip \
    "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip"
  sudo unzip -qo /tmp/deno.zip -d /usr/local/bin
  sudo chmod +x /usr/local/bin/deno
  rm -f /tmp/deno.zip
fi
say "deno $(deno --version | head -1)"

say "node, which the cli asks for"
command -v npm >/dev/null 2>&1 || sudo apt-get install -y -qq nodejs npm
say "everything the suite needs is here, log out and back in for the docker group"
