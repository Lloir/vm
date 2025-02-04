#!/bin/bash

# T&M Hansson IT AB © - 2021, https://www.hanssonit.se/

true
SCRIPT_NAME="Collabora (Integrated)"
SCRIPT_EXPLAINER="This script will install the integrated Collabora Office Server"
# shellcheck source=lib.sh
source /var/scripts/fetch_lib.sh || source <(curl -sL https://raw.githubusercontent.com/nextcloud/vm/master/lib.sh)

# Get all needed variables from the library
nc_update

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

# Check if root
root_check

# TODO: remove all functions with NC21.0.3 release
remove_all_office_apps() {
    # remove OnlyOffice-documentserver if installed
    if is_app_installed documentserver_community
    then
        nextcloud_occ app:remove documentserver_community
    fi

    # Disable OnlyOffice App if installed
    if is_app_installed onlyoffice
    then
        nextcloud_occ app:remove onlyoffice
    fi

    # remove richdocumentscode-documentserver if installed
    if is_app_installed richdocumentscode
    then
        nextcloud_occ app:remove richdocumentscode
    fi

    # Disable RichDocuments (Collabora App) if installed
    if is_app_installed richdocuments
    then
        nextcloud_occ app:remove richdocuments
    fi
}
remove_from_trusted_domains() {
    local element="$1"
    local count=0
    print_text_in_color "$ICyan" "Removing $element from trusted domains..."
    while [ "$count" -lt 10 ]
    do
        if [ "$(nextcloud_occ_no_check config:system:get trusted_domains "$count")" = "$element" ]
        then
            nextcloud_occ_no_check config:system:delete trusted_domains "$count"
            break
        else
            count=$((count+1))
        fi
    done
}

# Check if Collabora is installed using the new method
if ! is_app_installed richdocumentscode
then
    # Ask for installing
    install_popup "$SCRIPT_NAME"
else
    # Ask for removal or reinstallation
    reinstall_remove_menu "$SCRIPT_NAME"
    # Removal
    nextcloud_occ app:remove richdocumentscode
    # Disable Collabora App if activated
    if is_app_installed richdocuments
    then
        nextcloud_occ app:remove richdocuments
    fi
    # Show successful uninstall if applicable
    removal_popup "$SCRIPT_NAME"
fi

# Check if Collabora is installed using the old method
if does_this_docker_exist 'collabora/code'
then
    msg_box "Your server is compatible with the new way of installing Collabora. \
We will now remove the old docker and install the app from Nextcloud instead."
    # Remove docker image
    docker_prune_this 'collabora/code'
    # Revoke LE
    SUBDOMAIN=$(input_box_flow "Please enter the subdomain you are using for Collabora, e.g: office.yourdomain.com")
    if [ -f "$CERTFILES/$SUBDOMAIN/cert.pem" ]
    then
        yes no | certbot revoke --cert-path "$CERTFILES/$SUBDOMAIN/cert.pem"
        REMOVE_OLD="$(find "$LETSENCRYPTPATH/" -name "$SUBDOMAIN*")"
        for remove in $REMOVE_OLD
            do rm -rf "$remove"
        done
    fi
    # Remove Apache2 config
    if [ -f "$SITES_AVAILABLE/$SUBDOMAIN.conf" ]
    then
        a2dissite "$SUBDOMAIN".conf
        restart_webserver
        rm -f "$SITES_AVAILABLE/$SUBDOMAIN.conf"
    fi
    # Remove trusted domain
    remove_from_trusted_domains "$SUBDOMAIN"
fi

# Check if Onlyoffice is installed and remove every trace of it
if does_this_docker_exist 'onlyoffice/documentserver'
then
    msg_box "You can't run both Collabora and OnlyOffice on the same VM. We will now remove Onlyoffice from the server."
    # Remove docker image
    docker_prune_this 'onlyoffice/documentserver'
    # Revoke LE
    SUBDOMAIN=$(input_box_flow "Please enter the subdomain you are using for Onlyoffice, e.g: office.yourdomain.com")
    if [ -f "$CERTFILES/$SUBDOMAIN/cert.pem" ]
    then
        yes no | certbot revoke --cert-path "$CERTFILES/$SUBDOMAIN/cert.pem"
        REMOVE_OLD="$(find "$LETSENCRYPTPATH/" -name "$SUBDOMAIN*")"
        for remove in $REMOVE_OLD
            do rm -rf "$remove"
        done
    fi
    # Remove Apache2 config
    if [ -f "$SITES_AVAILABLE/$SUBDOMAIN.conf" ]
    then
        a2dissite "$SUBDOMAIN".conf
        restart_webserver
        rm -f "$SITES_AVAILABLE/$SUBDOMAIN.conf"
    fi
    # Remove trusted domain
    remove_from_trusted_domains "$SUBDOMAIN"
fi

# Remove all office apps
remove_all_office_apps

# Nextcloud 19 is required.
lowest_compatible_nc 19

ram_check 2 Collabora
cpu_check 2 Collabora

# Check if Nextcloud is installed with TLS
check_nextcloud_https "Collabora (Integrated)"

# Install Collabora
msg_box "We will now install Collabora.

Please note that it might take very long time to install the app, and you will not see any progress bar.

Please be patient, don't abort."
install_and_enable_app richdocuments
sleep 2
if install_and_enable_app richdocumentscode
then
    chown -R www-data:www-data "$NC_APPS_PATH"
    msg_box "Collabora was successfully installed."
else
    msg_box "The Collabora app failed to install. Please try again later."
fi

if ! is_app_installed richdocuments
then
    msg_box "The Collabora app failed to install. Please try again later."
fi

nextcloud_occ config:app:set richdocuments public_wopi_url --value="$(nextcloud_occ_no_check config:system:get overwrite.cli.url)"

# Just make sure the script exits
exit
