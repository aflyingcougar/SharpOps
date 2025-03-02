FROM ich777/steamcmd:cs2

RUN apt-get update && \
    apt-get -y install --no-install-recommends jq rsync unzip && \
    rm -rf /var/lib/apt/lists/*

ENV UPDATE_PLUGINS="true"

COPY /scripts/ /opt/scripts/
RUN chmod -R 770 /opt/scripts/

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]