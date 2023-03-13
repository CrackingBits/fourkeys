FROM dpage/pgadmin4:6.20

WORKDIR /pgadmin4

USER root
RUN mkdir -p /home/pgadmin
COPY --chown=pgadmin:root ./pgadmin-4-pgpass /home/pgadmin/.pgpass
COPY --chown=pgadmin:root ./pgadmin-4-servers.json /pgadmin4

RUN chmod 0600 /home/pgadmin/.pgpass
