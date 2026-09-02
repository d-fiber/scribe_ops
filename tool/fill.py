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

"""What a recipe looks like once every placeholder has an answer.

A recipe is not JSON or YAML as it sits: it carries `{{placeholders}}` that a
project's `params:` fills at render. Reading one at rest, to check it or to hand
it to OpenTofu, means answering them the way a render would, and a recipe says
what a plausible answer is in the `<recipe>.params.json` beside it.
"""

import json
import pathlib
import re
import sys


def params_of(recipe):
    """The values a project would write under `params:` for this recipe.

    The file is optional only for a recipe whose one placeholder is `name`,
    which `filled` answers on its own: every other placeholder needs an entry
    here, or `fill` refuses to guess one.
    """
    given = recipe.parent / (recipe.name.split(".")[0] + ".params.json")

    return json.loads(given.read_text()) if given.exists() else {}


def fill(recipe, params, source="the recipe"):
    """A recipe with an answer in the place of each of its placeholders.

    Three passes, because the place decides the form. A placeholder that is a
    whole string, or that stands where a JSON value starts, receives a literal,
    so a list arrives as a list. One written inside a longer string receives its
    bare scalar, since `"postgres:{{version}}"` wants the version and not a
    second pair of quotes. A placeholder [params] carries no answer for exits
    the run naming it, rather than becoming its own name: a real render
    would have refused the same placeholder, and a params.json that silently
    disagrees with what a recipe actually needs is worse than none at all.
    """

    def answer(name):
        if name not in params:
            sys.exit(f'[fill] {source}: "{name}" has no answer in params.json, and this does not guess one.')
        return json.dumps(params[name])

    recipe = re.sub(r'"\{\{([a-z_]+)\}\}"', lambda m: answer(m.group(1)), recipe)
    recipe = re.sub(r'(": |\[|, )\{\{([a-z_]+)\}\}', lambda m: m.group(1) + answer(m.group(2)), recipe)

    return re.sub(r"\{\{([a-z_]+)\}\}", lambda m: str(json.loads(answer(m.group(1)))), recipe)


def filled(path):
    """The recipe at [path], answered from the params file beside it.

    `name` answers itself when nothing else does: a real render never reads it
    from a project's `params:` either, since a resource's name comes from its
    declaration under `requires:`, not from what tunes it, and no example here
    stands for a real one a provider would accept.
    """
    recipe = pathlib.Path(path)
    params = {"name": "name", **params_of(recipe)}

    return fill(recipe.read_text(), params, source=str(recipe))


if __name__ == "__main__":
    sys.stdout.write(filled(sys.argv[1]))
