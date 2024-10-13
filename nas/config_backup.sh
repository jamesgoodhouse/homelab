#!/bin/bash

set -euf -o pipefail

backup_dir=/volume1/Config\ Backups/nas
backup_filename=backup.dss
backup_filepath="$backup_dir/$backup_filename"
epoch=$(date +%s)
tmp_backup_filepath="/tmp/$backup_filename.$epoch"

/usr/syno/bin/synoconfbkp export --filepath="$tmp_backup_filepath"

if [ ! -f "$backup_filepath" ] || [ "$(diff "$tmp_backup_filepath" "$backup_filepath")" != "" ]; then
  echo new backup found
  mv -f "$tmp_backup_filepath" "$backup_filepath"
  chmod 600 "$backup_filepath"
  chown admin:users "$backup_filepath"
else
  echo no new backup found
  rm -f "$tmp_backup_filepath"
fi
