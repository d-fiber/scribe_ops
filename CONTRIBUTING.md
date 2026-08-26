# Contributing

## Where the work goes

`dev` takes every commit. Nobody pushes to `main`: it moves by `promote`, which the owner runs by
hand with the version being released, and a push to `main` is what syncs the templates into the
CLI.

## Before you push

```
git config core.hooksPath .githooks
```

Once, per clone. The `pre-push` hook then runs everything the CI runs, and refuses the push when
one of them fails, so a red run costs you twelve seconds instead of a round trip. `git push
--no-verify` skips it, and the CI still catches what you skipped.

By hand, the same three:

```
bash tool/verify.sh
bash .github/headers/check.sh
bash .github/commits/check.sh origin/dev HEAD
```

The first is the one that matters. It renders every fixture with the real CLI and reads the output
with `docker compose config`, `caddy validate`, `caddy fmt` and a parse of the gateway document. It
needs Docker running and a checkout of the framework and of the CLI beside this one.

## What a commit message looks like

```
[TAG]: message
```

In English, imperative, no full stop, subject under 72 characters. The tags are `DEV`, `BUGFIX`,
`REFACTO`, `DOC`, `TEST`, `CI`, `PERF`, `SECURITY`, `BREAKING`, `REVERT` and `CHORE`. `RELEASE` is
written by the sync and never by hand.

A commit carries one subject. A template and the fixture that proves it are one subject; a template
and an unrelated workflow are two.

## How a version is written

`CHANGELOG.md` is the only place that says which version this repository holds: the first
numbered section is it. There is no version file, because two places that name a version are two
places that can disagree.

A green run on `dev` writes `v<version>` on the commit it ran against, once. The ruleset refuses
to move it or delete it afterwards, so raising the version is what names the next commit. `promote`
refuses a version that has never been tagged, which is how it knows the CI was green on it.

## The rulesets

`.github/rulesets/` holds what the repository refuses, and `apply.sh` puts it in place:

```
bash .github/rulesets/apply.sh d-fiber/scribe_ops
```

`Commit message format` on every branch, `Protect main` so nothing reaches it outside a pull
request or the promotion key, and `Tags are written once`.

## Adding a fixture

A fixture is a project the CLI can render: a `config.yaml`, a `lib/` holding one directory per node
it declares, and a `.env` carrying the values the compose interpolates. The values are dummies and
are committed, because what they prove is that the substitution happens, not what it substitutes.

Add one when a shape of stack is not covered yet. `minimal` mounts no package and names no
dashboard; `every-package` mounts all of them and names one. Between them they cover both branches
of every conditional the render carries today.

## What the suite cannot tell you

It reads documents, it does not start containers. An ordering between services, a probe that never
turns healthy, SQL replayed on an existing cluster and the environment a worker is missing are all
invisible to it. Starting the stack is worth doing and is not done here yet.
