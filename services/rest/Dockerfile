FROM postgrest/postgrest:v14.8 AS upstream

FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=upstream --chmod=755 /bin/ /upstream-bin/
RUN set -eux; \
    for candidate in /upstream-bin/postgrest /upstream-bin/bin/postgrest; do \
      if [ -f "$candidate" ]; then install -m 0755 "$candidate" /usr/bin/postgrest; break; fi; \
    done; \
    rm -rf /upstream-bin; \
    postgrest --version

USER 1000
EXPOSE 3000
CMD ["postgrest"]
