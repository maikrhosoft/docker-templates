#!/bin/sh
set -eu

: "${DOVECOT_USER:?DOVECOT_USER is required}"
: "${DOVECOT_PASSWORD:?DOVECOT_PASSWORD is required}"

DOVECOT_TLS_CN="${DOVECOT_TLS_CN:-localhost}"

mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail/vhosts

mkdir -p /etc/dovecot/certs

if [ ! -s /etc/dovecot/certs/dovecot.pem ] || [ ! -s /etc/dovecot/certs/dovecot.key ]; then
	openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days 825 \
		-subj "/CN=${DOVECOT_TLS_CN}" \
		-keyout /etc/dovecot/certs/dovecot.key \
		-out /etc/dovecot/certs/dovecot.pem
fi

printf '%s:{PLAIN}%s\n' "$DOVECOT_USER" "$DOVECOT_PASSWORD" > /etc/dovecot/users
chmod 600 /etc/dovecot/users /etc/dovecot/certs/dovecot.key /etc/dovecot/certs/dovecot.pem

exec dovecot -F
