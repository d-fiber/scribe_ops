# Testing

## What runs

`tool/verify.sh` is the whole suite, and the CI runs the same script with nothing added.

It lays the templates into a checkout of the CLI with the `.tmpl` suffix added back, builds the
binary from it, and renders every fixture under `fixtures/`. Then, per fixture:

| Check | What it catches |
| --- | --- |
| `docker compose config` | a mount whose source is missing, a document that does not merge, a service two fragments declare |
| a parse of `gateway/kong.yml` | a document Kong would refuse, and two routes answering the same path, which Kong accepts without a word |
| `caddy validate` | a site block with no address, a directive missing its argument |
| `caddy fmt` | a rendered file that is not what Caddy writes, which is an warning on every start |
| a search for `{{` | a placeholder the render left behind |

`shellcheck` reads the gateway entrypoint when it is installed, and says so when it is not.

## Why it renders first

Four of the twelve files are not valid for their own reader as they are written: `kong.yml` is not
YAML, the Caddyfile is not a Caddyfile, and `resources.yaml` and `replicas.yaml` hold a placeholder
where a key belongs. Checking them where they lie is not possible, so the suite checks what comes
out of the renderer instead.

The renderer is the real one. Four placeholders are blocks that `GatewayRender` and `ProxyRender`
build from the nodes a project declares, and a fixture cannot produce them without rebuilding the
node model. A second renderer would be a second thing to disagree with the first.

## What it needs

Docker running, a Dart SDK, **a Deno**, and a checkout of `scribe` and of `scribe_tools` beside
this one. `FRAMEWORK` and `TOOLS` name them when they sit elsewhere.

Deno is there for a reason worth knowing before it costs an hour: nothing here runs Deno, but
every command of the CLI goes through its tool check, not only the ones naming a tool in
`requiredTools`. A machine missing one of the four gets a report and an exit before `scribe run`
reads anything, and the report says `needs every tool above` without naming which. The CI installs
it at a pinned version, like the framework's own suite does.

## What it cannot do from a checkout alone

The suite renders with `scribe_tools@dev`, so a template that introduces a placeholder needs the
renderer that fills it to be there first. A new `{{name}}` is therefore two pushes, the CLI and
then this, in that order, and the run fails with `unresolved variable(s)` when they are the other
way round.

It is the ordering the framework already lives by, now running in both directions: the CLI reads
this repository's templates, and this repository renders with the CLI.

Everything the run writes lands in `.rendered/`, which is ignored. Nothing is written into either
of the neighbouring checkouts except `templates/ops/`, which the run replaces and which the CLI
repository is expected to hold as a copy anyway.
