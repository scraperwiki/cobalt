#!/bin/sh

# Default username

create_user() {
  USERNAME="$1"
  UID="$2"

  # Create the user
  gid=$(awk -F: '/^databox:/{print $3}' /etc/group)
  passwd_row="${USERNAME}:x:${UID}:${gid}::/home:/bin/bash"
  shadow_row="${USERNAME}:x:15607:0:99999:7:::"
  (
    flock -w 10 9 || exit 99
    { cat ${CO_STORAGE_DIR}/etc/passwd ; echo "$passwd_row" ; } > ${CO_STORAGE_DIR}/etc/passwd+
    mv ${CO_STORAGE_DIR}/etc/passwd+ ${CO_STORAGE_DIR}/etc/passwd

    cat ${CO_STORAGE_DIR}/etc/passwd > /opt/basejail/etc/passwd+
    mv /opt/basejail/etc/passwd+ /opt/basejail/etc/passwd

    { cat ${CO_STORAGE_DIR}/etc/shadow ; echo "$shadow_row" ; } > ${CO_STORAGE_DIR}/etc/shadow+
    mv ${CO_STORAGE_DIR}/etc/shadow+ ${CO_STORAGE_DIR}/etc/shadow

    cat /etc/group > /opt/basejail/etc/group+
    mv /opt/basejail/etc/group+ /opt/basejail/etc/group
   ) 9>${CO_STORAGE_DIR}/etc/passwd.cobalt.lock
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

  mkdir -p "${CO_STORAGE_DIR}/sshkeys/${USERNAME}"
}


delete_user_directories() {
  USERNAME="$1"
  rm -R "${CO_STORAGE_DIR}/home/$USERNAME"
}

update_jail() {
  BASEJAIL="$1"

  # User in the jail
}
