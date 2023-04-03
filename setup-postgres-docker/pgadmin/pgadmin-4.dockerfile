FROM dpage/pgadmin4:latest

WORKDIR /pgadmin4

USER root
COPY --chown=pgadmin:root ./pgadmin-4-servers.json /pgadmin4/

COPY ./pgadmin4.db /var/lib/pgadmin/
RUN chmod 0600 /var/lib/pgadmin/pgadmin4.db

# when /var/lib/pgadmin/storage/postgres_example.com/ is not volume
# this puts pgpass in place https://stackoverflow.com/questions/66578506/where-is-the-pgpass-file-in-pgadmin4-docker-container-when-this-file-is-mounted
COPY --chown=pgadmin:root ./pgadmin-4-pgpass /var/lib/pgadmin/storage/postgres_example.com/.pgpass
RUN chmod 0600 /var/lib/pgadmin/storage/postgres_example.com/.pgpass
