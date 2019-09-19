#!/bin/bash

set -x
set -o errexit
set -o pipefail

sync

# if custom config file exist then process them
CUSTOM_CONFIG_DIR="/elasticsearch/custom-config"
CONFIG_DIR="/elasticsearch/config"
CONFIG_FILE=$CONFIG_DIR/elasticsearch.yml
XPACK_SECURITY_CONFIG_FILE=$CONFIG_DIR/elasticsearch-xpack-security.yml

if [ "${XPACK_SECURITY_ENABLED}" == "true" ]; then
  ORIGINAL_PERMISSION=$(stat -c '%a' $CONFIG_FILE)
  yq merge -i --overwrite $CONFIG_FILE $XPACK_SECURITY_CONFIG_FILE
  chmod $ORIGINAL_PERMISSION $CONFIG_FILE
fi

if [ -d "$CUSTOM_CONFIG_DIR" ]; then

  configs=($(find $CUSTOM_CONFIG_DIR -maxdepth 1 -name "*.yaml"))
  configs+=($(find $CUSTOM_CONFIG_DIR -maxdepth 1 -name "*.yml"))
  if [ ${#configs[@]} -gt 0 ]; then
    config-merger.sh
  fi
fi

echo "Starting runit..."
exec /sbin/runsvdir -P /etc/service
