# Changelog

## 1.0.0

The first cut of `scribe_ops`, the templates a scribe stack is assembled from.

### What the repository holds

Twelve files, in four directories, each named the way the thing that reads it expects:

```
db/          roles.sql  jwt.sql
docker/      docker-compose.yaml  Dockerfile.api  Dockerfile.functions
             capacity.yaml  replicas.yaml  resources.yaml  tuning.yaml
gateway/     kong.yml  kong-entrypoint.sh
proxy/       Caddyfile
```

They arrive here from `scribe_tools/templates/ops/`, where they carried a `.tmpl` suffix that put
them out of reach of every tool that could have checked them. Without the suffix, `docker compose
config` reads the compose, `caddy validate` reads the Caddyfile, `psql` runs the SQL and
`shellcheck` reads the entrypoint.

### What the suite does

Four of the twelve carry `{{placeholders}}` that make them invalid for their own tool: `kong.yml`
is not YAML, the Caddyfile is not a Caddyfile, and `resources.yaml` and `replicas.yaml` hold a
placeholder where a key belongs. They are therefore never checked as they are written. The suite
renders them first, with the CLI that renders them in production, and checks what comes out.

The renderer is not reimplemented here, and that is the point: four of the placeholders are not
values but blocks that `GatewayRender` and `ProxyRender` build from the nodes a project declares.
A fixture cannot produce them without rebuilding the node model, and a second renderer is a second
thing to disagree with the first.

### How a change reaches the CLI

The suite copies this repository into a checkout of `scribe_tools`, adding the `.tmpl` suffix back,
and builds the binary from it. The promotion does the same copy against the real repository, so
the rename is exercised by every run rather than trusted once.
