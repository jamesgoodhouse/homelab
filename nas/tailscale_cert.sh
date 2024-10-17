#!/bin/bash

set -e

copy_if_different() {
  local source_file=$1
  local target_file=$2
  
  if [ ! -f "$target_file" ]; then
    echo "Copying $source_file to $target_file"
    cp "$source_file" "$target_file"
    return 0
  elif ! cmp -s "$source_file" "$target_file"; then
    echo "Copying $source_file to $target_file"
    cp "$source_file" "$target_file"
    return 0
  else
    echo "$target_file is up to date."
    return 1
  fi
}

restart_services() {
  echo "Restarting services"
  /bin/systemctl restart nginx
  /bin/systemctl restart pkgctl-WebDAVServer
  echo "Services restarted"
}

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

USER_HOME=$(eval echo ~"$SUDO_USER")
TEMPDIR="$USER_HOME/.tailscale_certs"
TS_DNS=$(/usr/local/bin/tailscale status --json | jq -r '.Self.DNSName | .[:-1]')
CERT_DIR="/usr/syno/etc/certificate/_archive"
DEFAULT_FILE_PATH="$CERT_DIR/DEFAULT"
DEFAULT_CERT_ID=$(cat "$DEFAULT_FILE_PATH")
INFO_FILE_PATH="$CERT_DIR/INFO"
SERVICES_FILE_PATH="$CERT_DIR/SERVICES"
TAILSCALE_CERT_ID=tailscale
TAILSCALE_CERT_DIR="$CERT_DIR/$TAILSCALE_CERT_ID"

CERTIFICATES_UPDATED=0

if ! jq -e ". | has(\"$TAILSCALE_CERT_ID\")" "$INFO_FILE_PATH" > /dev/null; then
  echo "Adding Tailscale to $INFO_FILE_PATH"
  jq --arg key "$TAILSCALE_CERT_ID" --argjson services "$(cat $SERVICES_FILE_PATH)" \
    '. + {($key): {"desc": "Tailscale", "services": $services}}' "$INFO_FILE_PATH" > "$INFO_FILE_PATH.tmp" && \
  mv "$INFO_FILE_PATH.tmp" "$INFO_FILE_PATH"
else
  echo "Tailscale already added to $INFO_FILE_PATH"
fi

mkdir -p "$TEMPDIR"
trap 'rm -rf "$TEMPDIR"' EXIT

echo "Fetching certificates"
/usr/local/bin/tailscale cert --cert-file "$TEMPDIR/$TS_DNS.crt" --key-file "$TEMPDIR/$TS_DNS.key" "$TS_DNS" > /dev/null

echo "Converting to PKCS #8 format"
/bin/openssl pkcs8 -topk8 -nocrypt -in "$TEMPDIR/$TS_DNS.key" -out "$TEMPDIR/p8file.pem"

mkdir -p "$TAILSCALE_CERT_DIR"
copy_if_different "$TEMPDIR/$TS_DNS.crt" "$TAILSCALE_CERT_DIR/cert.pem" && CERTIFICATES_UPDATED=1
copy_if_different "$TEMPDIR/$TS_DNS.crt" "$TAILSCALE_CERT_DIR/fullchain.pem" && CERTIFICATES_UPDATED=1
copy_if_different "$TEMPDIR/p8file.pem" "$TAILSCALE_CERT_DIR/privkey.pem" && CERTIFICATES_UPDATED=1

if [ "$DEFAULT_CERT_ID" != "$TAILSCALE_CERT_ID" ]; then
  echo "$TAILSCALE_CERT_ID" > "$DEFAULT_FILE_PATH"
fi

if [ "$CERTIFICATES_UPDATED" -eq 1 ]; then
  echo "Certificates updated"
  restart_services
else
  echo "Certificates up-to-date"
fi
