# power-dns

Minimal PowerDNS Authoritative stack based on Alpine + SQLite, designed to run as either:

- **master** with API/webserver enabled
- **slave** with `autosecondary` enabled and no web interface exposed

The container name is:

- `power-dns`

This project is intended to keep the deployment simple, reproducible and easy to bootstrap.

---

## Features

- PowerDNS Authoritative Server
- SQLite backend
- Docker-based deployment
- Bootstrap script for master/slave roles
- Optional PowerDNS API and webserver
- Autoprimary / autosecondary support for slaves
- Clean split between:
  - base compose
  - master compose
  - slave compose

---

## Project layout

```text
.
├── Dockerfile
├── bootstrap.sh
├── entrypoint.sh
├── docker-compose.yml
├── docker-compose.master.yml
├── docker-compose.slave.yml
└── data/
```

---

## Compose files

### `docker-compose.yml`
Base definition shared by all modes.

### `docker-compose.master.yml`
Adds the API/webserver port mapping:

- `8081:8081`

### `docker-compose.slave.yml`
Keeps only DNS ports exposed:

- `53/tcp`
- `53/udp`

---

## Ports

### Master
- `53/tcp`
- `53/udp`
- `8081/tcp`

### Slave
- `53/tcp`
- `53/udp`

The slave does **not** need the PowerDNS API or webserver exposed.

---

## Operating modes

### Master mode

Typical master configuration:

- `primary=yes`
- `secondary=yes`
- `autosecondary=no`
- `api=yes`
- `webserver=yes`

Use this mode when the server is the main administrative node.

Example:

```bash
./bootstrap.sh -k YOUR_API_KEY -p yes -s yes
```

---

### Slave mode

Typical slave configuration:

- `primary=no`
- `secondary=yes`
- `autosecondary=yes`
- `api=no`
- `webserver=no`

Use this mode when the server should automatically create secondary zones from a trusted master.

Example:

```bash
./bootstrap.sh -S -m 170.78.75.49 -n terminus.example.com
```

Where:

- `-S` enables slave profile
- `-m` is the master IP
- `-n` is the master nameserver stored in `supermasters`

> Important: the nameserver stored in `supermasters` must be saved **without a trailing dot**.

---

## Bootstrap script

The main entry point is:

```bash
./bootstrap.sh
```

### General options

```text
-k, --api-key VALUE
-w, --webserver-allow-from VALUE
-p, --primary yes|no
-s, --secondary yes|no
-f, --force-defaults
```

### Slave profile options

```text
-S, --slave
-m, --master-ip IP
-n, --master-ns FQDN
```

### Help

```bash
./bootstrap.sh -h
```

---

## Examples

### Start a master

```bash
./bootstrap.sh -k YOUR_API_KEY -p yes -s yes
```

### Start a slave

```bash
./bootstrap.sh -S -m 170.78.75.49 -n terminus.example.com
```

### Start with explicit defaults

```bash
./bootstrap.sh -f
```

---

## Environment variables

The stack supports these variables:

- `PDNS_API_KEY`
- `PDNS_WEBSERVER_ALLOW_FROM`
- `PDNS_PRIMARY`
- `PDNS_SECONDARY`
- `PDNS_AUTOSECONDARY`
- `PDNS_API`
- `PDNS_WEBSERVER`
- `PDNS_MASTER_IP`
- `PDNS_MASTER_NS`

The bootstrap script exports the required values before calling Docker Compose.

---

## SQLite backend

The SQLite database is stored in:

```text
/data/pdns.sqlite
```

On first run, `entrypoint.sh` initializes the schema automatically.

This includes:

- `domains`
- `records`
- `supermasters`
- `comments`
- `domainmetadata`
- `cryptokeys`
- `tsigkeys`

---

## Autoprimary / autosecondary

Slave auto-provisioning is based on:

- `secondary=yes`
- `autosecondary=yes`
- `supermasters` table populated with:
  - master IP
  - master nameserver
  - account

When the slave receives a valid `NOTIFY` from a configured supermaster, it can automatically:

1. create the secondary zone
2. perform AXFR from the master
3. commit the zone to SQLite

### Important note

The nameserver stored in `supermasters` must match one of the zone NS records reported by the master.

For example, if the zone publishes:

```text
example.com. NS ns1.example.com.
example.com. NS ns2.example.com.
```

then `supermasters.nameserver` should contain one of these values **without the trailing dot**:

```text
ns1.example.com
```

or

```text
ns2.example.com
```

If the value does not match exactly, auto-provisioning will fail.

---

## PowerDNS configuration

The generated `pdns.conf` is written to:

```text
/etc/pdns/pdns.conf
```

The process is started with:

```text
--config-dir=/etc/pdns
```

So `/etc/powerdns` is not used by this image.

---

## DNS ports and privileged execution

PowerDNS listens on port 53, so the container runs with enough privileges to bind privileged ports.

This is expected for authoritative DNS service.

---

## Typical workflow

### Master
1. Start the master container
2. Create zones
3. Maintain records
4. Increase SOA serial when needed
5. Let PowerDNS send `NOTIFY`

### Slave
1. Start the slave container
2. Configure autosecondary via bootstrap
3. Wait for `NOTIFY`
4. PowerDNS creates the secondary zone automatically
5. AXFR pulls the zone from the master

---

## Useful commands

### Check generated config

```bash
docker exec -it power-dns sh -c 'cat /etc/pdns/pdns.conf'
```

### Check running process

```bash
docker exec -it power-dns sh -c 'ps aux | grep [p]dns_server'
```

### Inspect supermasters

```bash
sqlite3 data/pdns.sqlite 'select ip,nameserver,account from supermasters;'
```

### Inspect domains

```bash
sqlite3 data/pdns.sqlite 'select id,name,master,type from domains;'
```

### View logs

```bash
docker logs -f power-dns
```

### Test SOA locally

```bash
dig @127.0.0.1 example.com SOA +noall +answer +authority +comments +norecurse
```

### Test NS locally

```bash
dig @127.0.0.1 example.com NS +noall +answer +norecurse
```

### Force NOTIFY from the master

```bash
docker exec -it power-dns pdns_control notify example.com
```

---

## Rebuild cleanly

### Master

```bash
docker compose -f docker-compose.yml -f docker-compose.master.yml up -d --build
```

### Slave

```bash
docker compose -f docker-compose.yml -f docker-compose.slave.yml up -d --build
```

---

## Notes

- `supermasters.nameserver` should be stored **without** a trailing dot
- published DNS data may still use trailing dots normally
- the slave can work without API/webserver
- the master usually keeps API/webserver enabled
- if the slave receives `NOTIFY` but does not create the zone, verify:
  - `autosecondary=yes`
  - correct `supermasters` IP
  - correct `supermasters.nameserver`
  - matching NS records in the master zone

---

## Status

This stack has been tested with:

- master mode
- slave mode
- autoprimary/autosecondary
- automatic zone creation on slave
- AXFR transfer and commit

---

## License

MIT
