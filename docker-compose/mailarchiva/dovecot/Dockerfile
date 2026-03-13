FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends dovecot-core dovecot-imapd ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 5000 vmail \
    && useradd -u 5000 -g vmail -m -d /var/mail/vhosts -s /usr/sbin/nologin vmail \
    && mkdir -p /var/mail/vhosts /etc/dovecot \
    && chown -R vmail:vmail /var/mail/vhosts

COPY conf/dovecot.conf /etc/dovecot/dovecot.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 143 993

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
