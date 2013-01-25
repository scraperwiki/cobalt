#!/bin/sh

# Default username

create_user() {
  USERNAME="$1"

  # Create the user
  max_uid=$(awk -F: '{print $3}' /etc/passwd | sort -n | tail -1)
  uid=$(($max_uid + 1))
  gid=$(awk -F: '/^databox:/{print $3}' /etc/group)
  passwd_row="${USERNAME}:x:${uid}:${gid}::/home:/bin/bash"
  shadow_row="${USERNAME}:x:15607:0:99999:7:::"
  (
    flock -w 2 9 || exit 99
    { cat /shared_etc/passwd ; echo "$passwd_row" ; } > /shared_etc/passwd+
    mv /shared_etc/passwd+ /shared_etc/passwd
    { cat /shared_etc/shadow ; echo "$shadow_row" ; } > /shared_etc/shadow+
    mv /shared_etc/shadow+ /shared_etc/shadow
  ) 9>/shared_etc/passwd.cobalt.lock
}

delete_user() {
  # To be implemented
  :
}

create_user_directories() {
  USERNAME="$1"

  # root
  mkdir -p /home/"${USERNAME}"

  # jail
  mkdir -p "/jails/${USERNAME}"

  # Users owns her home.
  chown -R "$USERNAME:" "/home/${USERNAME}"

  cp /etc/passwd /opt/basejail/etc/passwd-inflight
  mv /opt/basejail/etc/passwd-inflight /opt/basejail/etc/passwd

  mkdir -p "/opt/cobalt/etc/sshkeys/${USERNAME}"
}

furnish_box() {
  # Just a wrapper really, switches to the user, then runs
  # another function.
  USERNAME="$1"
  sudo -u "$USERNAME" sh -c ". ./code/box_lib.sh; furnish_as_user"
}

furnish_as_user() {
  # We can assume that this function is called from within an
  # 'su', so any changes to cd etc will be undone when we finish.
  BOXNAME="$(whoami)"
  TEMPLATES=/opt/cobalt/code/templates

  # Go home.  Note: We're not chrooted.
  cd /home/"$BOXNAME"

  # scraperwiki.json file
  # Slightly hairy shell, because the .json file cannot end in a
  # newline.
  sh $TEMPLATES/scraperwiki.json.template > scraperwiki.json

  # README.md
  sh $TEMPLATES/README.md.template $BOXNAME > README.md

  # Initiate git repository.
  git init .
  sh $TEMPLATES/gitignore.template > .gitignore
  git add README.md .gitignore
  git commit -m "Box created" --author="Scraperwiki <developers@scraperwiki.com>"

  # create public http directory
  mkdir http
  
  # create incoming directory for file uploads
  mkdir incoming

}

delete_user_directories() {
  USERNAME="$1"
  rm -R "/home/$USERNAME"
}

update_jail() {
  BASEJAIL="$1"

  # User in the jail
}

