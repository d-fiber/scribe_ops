# Testing

## What runs

Two workflows read this repository. `ci.yml` renders the fixtures without starting anything, and
`e2e.yml` starts a real stack.

`verify/tool/verify.sh` is the render check, and it is the `verify` job of `ci.yml`. It lays the
templates into a checkout of the CLI with the `.tmpl` suffix added back, builds the binary from it,
and renders every fixture under `verify/fixtures/`. Then, per fixture:

| Check | What it catches |
| --- | --- |
| `docker compose config` | a mount whose source is missing, a document that does not merge, a service two fragments declare |
| a parse of `gateway/kong.yml` | a document Kong would refuse, and two routes answering the same path, which Kong accepts without a word |
| `caddy validate` | a site block with no address, a directive missing its argument |
| `caddy fmt` | a rendered file that is not what Caddy writes, which is a warning on every start |
| a search for `{{` | a placeholder the render left behind |

`shellcheck` reads the gateway entrypoint when it is installed, and says so when it is not.

`e2e.yml` runs the scenarios under `verify/e2e_tests/`, each of which renders a fixture and then
starts services against the daemon of the runner. It splits them by what they cost.

| Job | Scenarios | When |
| --- | --- | --- |
| `e2e-light` | `00_datastores`, `02_gateway`, `12_two_projects` | every push to `dev` and `main`, every pull request, and the two triggers below |
| `e2e-heavy` | the ten others, in three sets | nightly at 03:17 UTC, and on `workflow_dispatch` |

The line between the two is one image. `services/database/Dockerfile` builds on
`supabase/postgres:15.8.1.085`, which is about 3 GB, and every scenario that starts `db` pays for
it. The three light ones never start it: `00` starts the cache and the queue, `02` starts the
gateway with its upstream deliberately down, and `12` starts the router with two gateways and two
proxies behind it. What the three pull together is a fraction of that one image.

The eleven scenarios that are not `00` and `01` are not executable files, so they are run with
`bash` and not by their own path. That is what the workflow does, and what the line below does.

```
bash verify/e2e_tests/01_database/scenario.sh
KEEP=1 bash verify/e2e_tests/03_stack/scenario.sh
```

`KEEP` leaves the stack up when the scenario ends, which is the only way to look at a failure from
the inside. Without it every scenario tears its stack down on the way out, whether it passed or
not.

## How the two jobs are shaped

`e2e-light` runs one scenario per runner. A push gets its three answers in parallel, and
`12_two_projects`, which holds host ports 80 and 443 for its router, has a machine to itself.

`e2e-heavy` does the opposite. Each of its sets runs on one runner, one scenario after another, so
the cluster image is pulled once and every scenario behind it in the set reuses what is already
unpacked. The sets group scenarios by the images they share.

| Set | Scenarios | What it pulls |
| --- | --- | --- |
| `cluster` | `01_database`, `05_restart`, `06_target`, `09_limits` | the cluster, the cache and the queue |
| `stack` | `03_stack`, `04_request`, `07_worker`, `10_hardening` | those, plus the Deno base the api and the worker build on, PostgREST, and dbmate |
| `packages` | `08_two_stacks`, `11_every_package` | those, plus what a mounted package brings: storage, imgproxy, realtime and OpenSearch |

A set does not stop at its first failure. Every scenario runs, its output is folded under its own
name, and the job names at the end each one that did not pass. A scenario that fails prints the
state of its services and the tail of their logs where it stopped, so the set is worth reading
from the top even when three of its four are green.

Between two scenarios the job prunes the containers and volumes nothing holds and prints what is left of
the disk, so the margin is in the log rather than in this file. Before any of that it deletes the
.NET, Android, Haskell and Swift toolchains the runner image carries and nothing here uses, which
is the room the `packages` set unpacks into.

## Why the images are not cached

They are pulled on every run. What controls the cost is how often a run happens, not a cache.

Caching `/var/lib/docker` with `actions/cache` does not hold. The tree belongs to root, so reading
and writing it needs `sudo` at every step; the daemon has to be stopped before the tree is read and
started again once it is back; and a data root is only loadable by the daemon that wrote it, while
the runner image moves that version without saying so.

`docker save` and `docker load` on the pinned images holds mechanically and does not pay. `docker
save` writes layers uncompressed, the cache of a repository is capped at 10 GB with the oldest
entry evicted first, and a single entry holding the cluster image would sit against that ceiling
and push out the pub cache `ci.yml` keeps. What comes back is one download to unpack, against a
registry pull that fans out across layers, so there is no margin to bank.

What is left is to pull less often, which is the split above: three scenarios answer every push,
ten answer once a night and whenever someone asks for them.

## What the two jobs do not do

Neither is a required check. `.github/rulesets/main.json` requires `verify`, `headers`, `version`
and `commits`, and a job that pulls from a public registry would let a rate limit on an address
shared by every runner block a merge. They are read, not leaned on.

`workflow_dispatch` and `schedule` are read from the default branch alone, so a nightly run carries
that branch, and asking for `e2e.yml` by hand from `dev` needs `--ref dev`.

Five services and the router carry `no-new-privileges`, which a Docker installed from snap refuses.
The runners install Docker from the official repository, so the hardening the scenarios check is
the hardening that ships. A machine running the snap package fails `10_hardening` and everything
`e2e-heavy` starts, and the answer is the other package, never the removal of the setting.

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
this one. `FRAMEWORK` and `TOOLS` name them when they sit elsewhere. The scenarios need the same
four things as the render check, and build the same binary from the same templates before they
start anything.

Deno is there for a reason worth knowing before it costs an hour: nothing here runs Deno, but
every command of the CLI goes through its tool check, not only the ones naming a tool in
`requiredTools`. A machine missing one of the four gets a report and an exit before `scribe run`
reads anything, and the report says `needs every tool above` without naming which. Both workflows
install it at the version `ci.yml` pins, like the framework's own suite does.

## What it cannot do from a checkout alone

The suite renders with `scribe_tools@dev`, so a template that introduces a placeholder needs the
renderer that fills it to be there first. A new `{{name}}` is therefore two pushes, the CLI and
then this, in that order, and the run fails with `unresolved variable(s)` when they are the other
way round.

It is the ordering the framework already lives by, now running in both directions: the CLI reads
this repository's templates, and this repository renders with the CLI.

What the render check writes lands in `verify/.rendered/` and what a scenario writes lands in
`verify/.e2e/`, both of which are ignored. Nothing is written into either of the neighbouring
checkouts except `templates/deploy/` and `out/`, which the run replaces and which the CLI
repository is expected to hold as a copy anyway.
