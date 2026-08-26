FROM supabase/edge-runtime:v1.71.2 AS upstream

FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=upstream --chmod=755 /usr/local/bin/edge-runtime /usr/local/bin/edge-runtime

EXPOSE 9000
ENTRYPOINT ["edge-runtime"]
