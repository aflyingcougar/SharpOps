FROM ich777/steamcmd:cs2

RUN apt-get update && \
    apt-get -y install --no-install-recommends jq unzip && \
    rm -rf /var/lib/apt/lists/*

COPY /scripts/ /opt/scripts/
RUN chmod -R 770 /opt/scripts/

ENTRYPOINT ["/opt/scripts/entrypoint.sh"]