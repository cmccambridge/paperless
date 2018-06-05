#!/bin/bash

require() {
    : "${!1:? "ERROR: Must set $1 in unRAID template or Docker commandline!"}"
}

verify_required_env_vars() {
    require "PAPERLESS_PASSPHRASE"
    require "PAPERLESS_SUPERUSER_LOGIN"
    require "PAPERLESS_SUPERUSER_PASSWORD"
    require "PAPERLESS_SUPERUSER_EMAIL"
    require "PAPERLESS_CONSUMPTION_DIR"
    require "PAPERLESS_EXPORT_DIR"
}

ensure_paperless_conf() {
    # check for existing paperless.conf and create if absent
    if [[ ! -f /config/paperless.conf ]] ; then
        echo "No /config/paperless.conf found. Creating default..."
        cp /usr/src/paperless/paperless.conf.example /config/paperless.conf
        chown paperless:paperless /config/paperless.conf
        chmod 600 /config/paperless.conf
        # propagate consumption and export directories
        local ESC_CONSUME_DIR=$(echo ${PAPERLESS_CONSUMPTION_DIR} | sed 's/[&/\]/\\&/g')
        sed -i 's/PAPERLESS_CONSUMPTION_DIR=.*/PAPERLESS_CONSUMPTION_DIR="'"${ESC_CONSUME_DIR}"'"/' /config/paperless.conf
        local ESC_EXPORT_DIR=$(echo ${PAPERLESS_EXPORT_DIR} | sed 's/[&/\]/\\&/g')
        sed -i 's/PAPERLESS_EXPORT_DIR=.*/PAPERLESS_EXPORT_DIR="'"${ESC_EXPORT_DIR}"'"/' /config/paperless.conf

        # seed the PAPERLESS_SECRET_KEY with alphanumeric and some special chars that won't need escapes
        local NEW_SECRET=$(cat /dev/urandom | tr -dc '!#$%*+,.=?@_a-zA-Z0-9' | fold -w 64 | head -n 1)
	local RANDOMIZE_TIME=$(date "+%F at %T")
        sed -i 's/^\s*#*\s*PAPERLESS_SECRET_KEY.*/# Randomized by container intialization on '"${RANDOMIZE_TIME}"'\nPAPERLESS_SECRET_KEY="'"${NEW_SECRET}"'"/' /config/paperless.conf

        # knock out the PAPERLESS_PASSPHRASE - we'll set it in the unRAID template
        sed -i 's/^PAPERLESS_PASSPHRASE.*/#PAPERLESS_PASSPHRASE="" # Set by unRAID template parameters/' /config/paperless.conf
    fi
}

# Cribbing from https://stackoverflow.com/a/45577488
ensure_django_superuser() {
    python3 -c "
import os;
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'paperless.settings')
import django;
django.setup();

from django.contrib.auth.management.commands.createsuperuser import get_user_model;
try:
    get_user_model()._default_manager.db_manager('default').get_by_natural_key('${PAPERLESS_SUPERUSER_LOGIN}')
except get_user_model().DoesNotExist:
    print('Creating user ${PAPERLESS_SUPERUSER_LOGIN} (${PAPERLESS_SUPERUSER_EMAIL})...')
    get_user_model()._default_manager.db_manager('default').create_superuser(
        username='${PAPERLESS_SUPERUSER_LOGIN}',
        email='${PAPERLESS_SUPERUSER_EMAIL}',
        password='${PAPERLESS_SUPERUSER_PASSWORD}')
    print('Done.')
else:
    print('Superuser ${PAPERLESS_SUPERUSER_LOGIN} already exists. Done.')
"
}

unraid_initialize() {
    verify_required_env_vars
    ensure_paperless_conf
}

unraid_post_migrations() {
    ensure_django_superuser
}

