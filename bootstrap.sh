#!/bin/sh
set -e

show_help() {
    cat <<'EOF'
Usage:
  ./bootstrap.sh [options]

General options:
  -k, --api-key VALUE            PowerDNS API key
  -w, --webserver-allow-from V   PDNS_WEBSERVER_ALLOW_FROM
  -p, --primary yes|no           PDNS_PRIMARY
  -s, --secondary yes|no         PDNS_SECONDARY
  -f, --force-defaults           Use built-in defaults for general mode

Slave profile:
  -S, --slave                    Configure a pure slave profile
  -m, --master-ip IP             Required with --slave
  -n, --master-ns FQDN           Optional autoprimary nameserver for supermasters

Other:
  -h, --help                     Show this help

Priority in general mode:
  1. Environment variables
  2. Command line options
  3. Built-in defaults, but only with -f / --force-defaults

Built-in defaults for general mode:
  PDNS_API_KEY=change
  PDNS_WEBSERVER_ALLOW_FROM=0.0.0.0/0,::/0
  PDNS_PRIMARY=yes
  PDNS_SECONDARY=yes
  PDNS_AUTOSECONDARY=no
  PDNS_API=yes
  PDNS_WEBSERVER=yes
  PDNS_MASTER_IP=0.0.0.0/0,::/0
  PDNS_MASTER_NS=

Slave profile forces:
  PDNS_PRIMARY=no
  PDNS_SECONDARY=yes
  PDNS_AUTOSECONDARY=yes
  PDNS_API=no
  PDNS_WEBSERVER=no

Notes:
  -S / --slave is exclusive and cannot be combined with:
    -k / --api-key
    -w / --webserver-allow-from
    -p / --primary
    -s / --secondary
    -f / --force-defaults
EOF
}

API_KEY_OPT=""
ALLOW_FROM_OPT=""
PRIMARY_OPT=""
SECONDARY_OPT=""
FORCE_DEFAULTS="no"
SLAVE_MODE="no"
MASTER_IP_OPT=""
MASTER_NS_OPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -k|--api-key)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            API_KEY_OPT="$2"
            shift 2
            ;;
        -w|--webserver-allow-from)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            ALLOW_FROM_OPT="$2"
            shift 2
            ;;
        -p|--primary)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            PRIMARY_OPT="$2"
            shift 2
            ;;
        -s|--secondary)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            SECONDARY_OPT="$2"
            shift 2
            ;;
        -m|--master-ip)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            MASTER_IP_OPT="$2"
            shift 2
            ;;
        -n|--master-ns)
            [ $# -lt 2 ] && { echo "Missing value for $1" >&2; exit 1; }
            MASTER_NS_OPT="$2"
            shift 2
            ;;
        -f|--force-defaults)
            FORCE_DEFAULTS="yes"
            shift
            ;;
        -S|--slave)
            SLAVE_MODE="yes"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help" >&2
            exit 1
            ;;
    esac
done

validate_ipv4() {
    ip="$1"
    echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    OLDIFS="$IFS"
    IFS=.
    set -- $ip
    IFS="$OLDIFS"
    [ "$1" -le 255 ] && [ "$2" -le 255 ] && [ "$3" -le 255 ] && [ "$4" -le 255 ]
}

normalize_fqdn_no_dot() {
    value="$1"
    value="${value%.}"
    echo "$value"
}

run_master_compose() {
    docker compose -f docker-compose.yml -f docker-compose.master.yml up -d --build
}

run_slave_compose() {
    docker compose -f docker-compose.yml -f docker-compose.slave.yml up -d --build
}

if [ "$SLAVE_MODE" = "yes" ]; then
    if [ -n "$API_KEY_OPT" ] || \
       [ -n "$ALLOW_FROM_OPT" ] || \
       [ -n "$PRIMARY_OPT" ] || \
       [ -n "$SECONDARY_OPT" ] || \
       [ "$FORCE_DEFAULTS" = "yes" ] || \
       [ -n "${PDNS_API_KEY:-}" ] || \
       [ -n "${PDNS_WEBSERVER_ALLOW_FROM:-}" ] || \
       [ -n "${PDNS_PRIMARY:-}" ] || \
       [ -n "${PDNS_SECONDARY:-}" ] || \
       [ -n "${PDNS_API:-}" ] || \
       [ -n "${PDNS_WEBSERVER:-}" ] || \
       [ -n "${PDNS_AUTOSECONDARY:-}" ]; then
        echo "--slave is exclusive and cannot be combined with general/master options." >&2
        exit 1
    fi

    MASTER_IP_FINAL="${PDNS_MASTER_IP:-$MASTER_IP_OPT}"
    MASTER_NS_FINAL="${PDNS_MASTER_NS:-$MASTER_NS_OPT}"

    if [ -z "$MASTER_IP_FINAL" ]; then
        echo "--slave requires --master-ip" >&2
        exit 1
    fi

    if ! validate_ipv4 "$MASTER_IP_FINAL"; then
        echo "Invalid master IP: $MASTER_IP_FINAL" >&2
        exit 1
    fi

    export PDNS_MASTER_IP="$MASTER_IP_FINAL"
    export PDNS_MASTER_NS="$(normalize_fqdn_no_dot "$MASTER_NS_FINAL")"
    export PDNS_PRIMARY="no"
    export PDNS_SECONDARY="yes"
    export PDNS_AUTOSECONDARY="yes"
    export PDNS_API="no"
    export PDNS_WEBSERVER="no"

    echo "SLAVE MODE ENABLED"
    echo "PDNS_MASTER_IP=$PDNS_MASTER_IP"
    echo "PDNS_MASTER_NS=$PDNS_MASTER_NS"
    echo "PDNS_PRIMARY=$PDNS_PRIMARY"
    echo "PDNS_SECONDARY=$PDNS_SECONDARY"
    echo "PDNS_AUTOSECONDARY=$PDNS_AUTOSECONDARY"
    echo "PDNS_API=$PDNS_API"
    echo "PDNS_WEBSERVER=$PDNS_WEBSERVER"

    run_slave_compose
    exit 0
fi

PDNS_API_KEY_FINAL="${PDNS_API_KEY:-$API_KEY_OPT}"
PDNS_WEBSERVER_ALLOW_FROM_FINAL="${PDNS_WEBSERVER_ALLOW_FROM:-$ALLOW_FROM_OPT}"
PDNS_PRIMARY_FINAL="${PDNS_PRIMARY:-$PRIMARY_OPT}"
PDNS_SECONDARY_FINAL="${PDNS_SECONDARY:-$SECONDARY_OPT}"

ANY_EXPLICIT="no"
[ -n "$PDNS_API_KEY_FINAL" ] && ANY_EXPLICIT="yes"
[ -n "$PDNS_WEBSERVER_ALLOW_FROM_FINAL" ] && ANY_EXPLICIT="yes"
[ -n "$PDNS_PRIMARY_FINAL" ] && ANY_EXPLICIT="yes"
[ -n "$PDNS_SECONDARY_FINAL" ] && ANY_EXPLICIT="yes"

if [ "$ANY_EXPLICIT" = "no" ] && [ "$FORCE_DEFAULTS" != "yes" ]; then
    echo "No configuration was provided." >&2
    echo "Refusing to use defaults silently." >&2
    echo "Pass values through env or flags, or use -f / --force-defaults explicitly." >&2
    echo >&2
    show_help >&2
    exit 1
fi

if [ "$ANY_EXPLICIT" = "no" ] && [ "$FORCE_DEFAULTS" = "yes" ]; then
    echo "WARNING: using built-in defaults." >&2
    echo "WARNING: PDNS_API_KEY=change is a terrible long-term idea." >&2
    echo "WARNING: you are now officially too lazy." >&2
fi

export PDNS_API_KEY="${PDNS_API_KEY_FINAL:-change}"
export PDNS_WEBSERVER_ALLOW_FROM="${PDNS_WEBSERVER_ALLOW_FROM_FINAL:-0.0.0.0/0,::/0}"
export PDNS_PRIMARY="${PDNS_PRIMARY_FINAL:-yes}"
export PDNS_SECONDARY="${PDNS_SECONDARY_FINAL:-yes}"
export PDNS_AUTOSECONDARY="${PDNS_AUTOSECONDARY:-no}"
export PDNS_API="${PDNS_API:-yes}"
export PDNS_WEBSERVER="${PDNS_WEBSERVER:-yes}"
export PDNS_MASTER_IP="${PDNS_MASTER_IP:-0.0.0.0/0,::/0}"
export PDNS_MASTER_NS="$(normalize_fqdn_no_dot "${PDNS_MASTER_NS:-}")"

case "$PDNS_PRIMARY" in
    yes|no) ;;
    *) echo "PDNS_PRIMARY must be yes or no" >&2; exit 1 ;;
esac

case "$PDNS_SECONDARY" in
    yes|no) ;;
    *) echo "PDNS_SECONDARY must be yes or no" >&2; exit 1 ;;
esac

case "$PDNS_AUTOSECONDARY" in
    yes|no) ;;
    *) echo "PDNS_AUTOSECONDARY must be yes or no" >&2; exit 1 ;;
esac

case "$PDNS_API" in
    yes|no) ;;
    *) echo "PDNS_API must be yes or no" >&2; exit 1 ;;
esac

case "$PDNS_WEBSERVER" in
    yes|no) ;;
    *) echo "PDNS_WEBSERVER must be yes or no" >&2; exit 1 ;;
esac

echo "MASTER/GENERAL MODE"
echo "PDNS_API_KEY=$PDNS_API_KEY"
echo "PDNS_WEBSERVER_ALLOW_FROM=$PDNS_WEBSERVER_ALLOW_FROM"
echo "PDNS_PRIMARY=$PDNS_PRIMARY"
echo "PDNS_SECONDARY=$PDNS_SECONDARY"
echo "PDNS_AUTOSECONDARY=$PDNS_AUTOSECONDARY"
echo "PDNS_API=$PDNS_API"
echo "PDNS_WEBSERVER=$PDNS_WEBSERVER"
echo "PDNS_MASTER_IP=$PDNS_MASTER_IP"
echo "PDNS_MASTER_NS=$PDNS_MASTER_NS"

run_master_compose
