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

Docker running, a Dart SDK, and a checkout of `scribe` and of `scribe_tools` beside this one.
`FRAMEWORK` and `TOOLS` name them when they sit elsewhere.

Everything the run writes lands in `.rendered/`, which is ignored. Nothing is written into either
of the neighbouring checkouts except `templates/ops/`, which the run replaces and which the CLI
repository is expected to hold as a copy anyway.
