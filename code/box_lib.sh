#!/bin/sh

# Default username

PASSWD_DIR=/var/lib/extrausers

create_user() {
  USERNAME="$1"
  UID="$2"

  # Create the user
  gid=$(awk -F: '/^databox:/{print $3}' /etc/group)
  passwd_row="${USERNAME}:x:${UID}:${gid}::/home:/bin/bash"
  shadow_row="${USERNAME}:x:15607:0:99999:7:::"
  (
    flock -w 10 9 || exit 99
    { cat ${PASSWD_DIR}/passwd ; echo "$passwd_row" ; } > ${PASSWD_DIR}/passwd+
    mv ${PASSWD_DIR}/passwd+ ${PASSWD_DIR}/passwd


    { cat ${PASSWD_DIR}/shadow ; echo "$shadow_row" ; } > ${PASSWD_DIR}/shadow+
    mv ${PASSWD_DIR}/shadow+ ${PASSWD_DIR}/shadow

   ) 9>${PASSWD_DIR}/passwd.cobalt.lock
}

delete_user() {
  # To be implemented
  :
}

create_user_directories() {
  USERNAME="$1"

  # root
  mkdir -p ${CO_STORAGE_DIR}/home/"${USERNAME}"

  # jail
  mkdir -p "/jails/${USERNAME}"

  # Users owns her home.
  chown -R "$USERNAME:" "${CO_STORAGE_DIR}/home/${USERNAME}"
}


delete_user_directories() {
  USERNAME="$1"
  rm -R "${CO_STORAGE_DIR}/home/$USERNAME"
}

update_jail() {
  BASEJAIL="$1"

  # User in the jail
}
