#!/bin/sh
set -e

DB=/data/pdns.sqlite
CONF_DIR=/etc/pdns
CONF_FILE=/etc/pdns/pdns.conf

mkdir -p /data
mkdir -p "$CONF_DIR"

if [ ! -f "$DB" ]; then
    echo "Initializing SQLite database..."

    sqlite3 "$DB" <<'EOF'
PRAGMA foreign_keys = 1;

CREATE TABLE domains (
  id                    INTEGER PRIMARY KEY,
  name                  VARCHAR(255) NOT NULL COLLATE NOCASE,
  master                VARCHAR(128) DEFAULT NULL,
  last_check            INTEGER DEFAULT NULL,
  type                  VARCHAR(8) NOT NULL,
  notified_serial       INTEGER DEFAULT NULL,
  account               VARCHAR(40) DEFAULT NULL,
  options               VARCHAR(65535) DEFAULT NULL,
  catalog               VARCHAR(255) DEFAULT NULL
);

CREATE UNIQUE INDEX name_index ON domains(name);
CREATE INDEX catalog_idx ON domains(catalog);

CREATE TABLE records (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER DEFAULT NULL,
  name                  VARCHAR(255) DEFAULT NULL,
  type                  VARCHAR(10) DEFAULT NULL,
  content               VARCHAR(65535) DEFAULT NULL,
  ttl                   INTEGER DEFAULT NULL,
  prio                  INTEGER DEFAULT NULL,
  disabled              BOOLEAN DEFAULT 0,
  ordername             VARCHAR(255),
  auth                  BOOL DEFAULT 1,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX records_lookup_idx ON records(name, type);
CREATE INDEX records_lookup_id_idx ON records(domain_id, name, type);
CREATE INDEX records_order_idx ON records(domain_id, ordername);

CREATE TABLE supermasters (
  ip                    VARCHAR(64) NOT NULL,
  nameserver            VARCHAR(255) NOT NULL COLLATE NOCASE,
  account               VARCHAR(40) NOT NULL
);

CREATE UNIQUE INDEX ip_nameserver_pk ON supermasters(ip, nameserver);

CREATE TABLE comments (
  id                    INTEGER PRIMARY KEY,
  domain_id             INTEGER NOT NULL,
  name                  VARCHAR(255) NOT NULL,
  type                  VARCHAR(10) NOT NULL,
  modified_at           INT NOT NULL,
  account               VARCHAR(40) DEFAULT NULL,
  comment               VARCHAR(65535) NOT NULL,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX comments_idx ON comments(domain_id, name, type);
CREATE INDEX comments_order_idx ON comments(domain_id, modified_at);

CREATE TABLE domainmetadata (
  id                    INTEGER PRIMARY KEY,
  domain_id             INT NOT NULL,
  kind                  VARCHAR(32) COLLATE NOCASE,
  content               TEXT,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX domainmetaidindex ON domainmetadata(domain_id);

CREATE TABLE cryptokeys (
  id                    INTEGER PRIMARY KEY,
  domain_id             INT NOT NULL,
  flags                 INT NOT NULL,
  active                BOOL,
  published             BOOL DEFAULT 1,
  content               TEXT,
  FOREIGN KEY(domain_id) REFERENCES domains(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX domainidindex ON cryptokeys(domain_id);

CREATE TABLE tsigkeys (
  id                    INTEGER PRIMARY KEY,
  name                  VARCHAR(255) COLLATE NOCASE,
  algorithm             VARCHAR(50) COLLATE NOCASE,
  secret                VARCHAR(255)
);

CREATE UNIQUE INDEX namealgoindex ON tsigkeys(name, algorithm);
EOF
fi

PDNS_API="${PDNS_API:-yes}"
PDNS_WEBSERVER="${PDNS_WEBSERVER:-yes}"
PDNS_API_KEY="${PDNS_API_KEY:-changeme}"
PDNS_WEBSERVER_ALLOW_FROM="${PDNS_WEBSERVER_ALLOW_FROM:-0.0.0.0/0,::/0}"
PDNS_PRIMARY="${PDNS_PRIMARY:-yes}"
PDNS_SECONDARY="${PDNS_SECONDARY:-yes}"
PDNS_AUTOSECONDARY="${PDNS_AUTOSECONDARY:-no}"
PDNS_MASTER_IP="${PDNS_MASTER_IP:-0.0.0.0/0,::/0}"
PDNS_MASTER_NS="${PDNS_MASTER_NS:-}"

cat >"$CONF_FILE" <<EOF
launch=gsqlite3
gsqlite3-database=/data/pdns.sqlite
gsqlite3-dnssec=yes

default-soa-edit=INCEPTION-INCREMENT
default-soa-edit-signed=INCEPTION-INCREMENT
default-ttl=3600

primary=${PDNS_PRIMARY}
secondary=${PDNS_SECONDARY}
autosecondary=${PDNS_AUTOSECONDARY}

allow-notify-from=${PDNS_MASTER_IP}
allow-axfr-ips=0.0.0.0/0
allow-unsigned-notify=yes
allow-unsigned-autoprimary=yes

api=${PDNS_API}
webserver=${PDNS_WEBSERVER}
EOF

if [ "$PDNS_API" = "yes" ]; then
cat >>"$CONF_FILE" <<EOF
api-key=${PDNS_API_KEY}
EOF
fi

if [ "$PDNS_WEBSERVER" = "yes" ]; then
cat >>"$CONF_FILE" <<EOF
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=${PDNS_WEBSERVER_ALLOW_FROM}
EOF
fi

if [ "$PDNS_SECONDARY" = "yes" ] && [ -n "$PDNS_MASTER_NS" ] && [ -n "$PDNS_MASTER_IP" ] && [ "$PDNS_MASTER_IP" != "0.0.0.0/0,::/0" ]; then
    sqlite3 "$DB" <<EOF
INSERT OR IGNORE INTO supermasters (ip, nameserver, account)
VALUES ('${PDNS_MASTER_IP}', '${PDNS_MASTER_NS}', 'default');
EOF
fi

exec /usr/sbin/pdns_server --daemon=no --guardian=no --config-dir="$CONF_DIR"
