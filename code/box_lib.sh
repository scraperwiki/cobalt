#!/bin/sh

# Default username

create_user() {
  USERNAME="$1"

  # Create the user
  useradd  -g databox -s /bin/bash --home /home "${USERNAME}"
}

delete_user() {
  userdel "$1"
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
  ORG=$(dirname "$USERNAME")
  CRON_TAB_DIR="/var/spool/cron/crontabs/${ORG}"
  mkdir -p ${CRON_TAB_DIR}
  chmod 1730 ${CRON_TAB_DIR}
  chown :crontab ${CRON_TAB_DIR}
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
  mkdir /home/$BOXNAME/http

}

delete_user_directories() {
  USERNAME="$1"
  rm -R "/home/$USERNAME"
}

update_jail() {
  BASEJAIL="$1"

  # User in the jail
}

