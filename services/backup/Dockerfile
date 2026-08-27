FROM supabase/postgres:15.8.1.085

USER root

RUN set -eux; \
    nixbin="$(dirname "$(readlink -f /usr/bin/psql)")"; \
    apt-get update; \
    apt-get install -y --no-install-recommends pgbackrest; \
    rm -rf /var/lib/apt/lists/*; \
    for tool in psql pg_isready pg_dump pg_dumpall pg_restore; do \
      if [ -x "$nixbin/$tool" ]; then ln -sf "$nixbin/$tool" "/usr/bin/$tool"; fi; \
    done; \
    psql --version; \
    pg_isready --version

RUN mkdir -p /var/log/pgbackrest /var/spool/pgbackrest \
    && chown -R postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest

COPY run-init-scripts.sh /docker-entrypoint-initdb.d/zz-run-init-scripts.sh
RUN chmod 0755 /docker-entrypoint-initdb.d/zz-run-init-scripts.sh

COPY backup.sh /usr/local/bin/scribe-backup
RUN chmod 0755 /usr/local/bin/scribe-backup

FROM postgres:15.19-alpine

RUN deluser postgres 2>/dev/null || true; \
    delgroup postgres 2>/dev/null || true; \
    addgroup -g 106 postgres; \
    adduser -D -u 105 -G postgres postgres; \
    install -d -o postgres -g postgres /backups

COPY dump.sh /usr/local/bin/scribe-dump
COPY restore.sh /usr/local/bin/scribe-restore
RUN chmod 0755 /usr/local/bin/scribe-dump /usr/local/bin/scribe-restore

USER postgres
