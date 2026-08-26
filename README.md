# scribe_ops

The templates a scribe stack is assembled from: the compose, the gateway, the proxy, the
Dockerfiles and the SQL a cluster runs before it accepts a connection.

```
db/          roles.sql  jwt.sql
docker/      docker-compose.yaml  Dockerfile.api  Dockerfile.functions
             capacity.yaml  replicas.yaml  resources.yaml  tuning.yaml
gateway/     kong.yml  kong-entrypoint.sh
proxy/       Caddyfile
```

They live here rather than in the CLI so that the tool that reads each of them can be pointed at
it. In `scribe_tools` they carry a `.tmpl` suffix, which keeps them out of reach of `deno fmt` and
the Dart analyser and, in the same movement, out of reach of `docker compose config`, `caddy
validate` and `psql`. Here they carry the name the reader expects.

## Running the suite

```
bash tool/verify.sh
```

It expects a checkout of the framework and one of the CLI beside this one, and takes `FRAMEWORK`
and `TOOLS` when they sit elsewhere. Docker has to be running: every check is the real tool on the
real output.

## What a change costs

Four of the twelve files carry `{{placeholders}}`, and four of those placeholders are blocks the
CLI builds from the nodes a project declares. Nothing here can be checked as it is written, so the
suite renders a fixture first, with the CLI that renders it in production, and reads what comes
out. There is no second renderer in this repository, on purpose.

## How it reaches the CLI

`dev` takes the work, `promote` puts it on `main` under a tag, and a push to `main` copies the
files into `d-fiber/scribe_tools@dev` with the suffix added back. The suite does the same copy on
every run, so the rename is exercised rather than trusted.
