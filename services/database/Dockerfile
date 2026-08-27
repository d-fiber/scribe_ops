FROM supabase/postgres:15.8.1.085

USER root

RUN set -eux; \
    nixbin="$(dirname "$(readlink -f /usr/bin/psql)")"; \
    apt-get update; \
    rm -rf /var/lib/apt/lists/*; \
    for tool in psql pg_isready pg_dump pg_dumpall pg_restore; do \
      if [ -x "$nixbin/$tool" ]; then ln -sf "$nixbin/$tool" "/usr/bin/$tool"; fi; \
    done; \
    psql --version; \
    pg_isready --version


COPY run-init-scripts.sh /docker-entrypoint-initdb.d/zz-run-init-scripts.sh
RUN chmod 0755 /docker-entrypoint-initdb.d/zz-run-init-scripts.sh
