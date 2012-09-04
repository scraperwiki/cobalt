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
}

furnish_box() {
  # Just a wrapper really, switches to the user, then runs
  # another function.
  USERNAME="$1"
  su -c ". ./code/box_lib.sh; furnish_as_user" "$USERNAME"
}

furnish_as_user() {
  # We can assume that this function is called from within an
  # 'su', so any changes to cd etc will be undone when we finish.

  # Go home.  Note: We're not chrooted.
  cd /home/"$(whoami)"

  # Initiate git repository.
  git init .

  # scraperwiki.json file
  # Slightly hairy shell, because the .json file cannot end in a
  # newline.
  printf > scraperwiki.json "%s" "$(cat <<EOF
{}
EOF
)"

  # README.md
  cat > README.md <<EOF
ScraperWiki box $(whoami)

This is the README.md file for your box.

=======
We recommend that you edit this file and describe your box.
EOF

  # create public http directory
  mkdir /home/$(whoami)/http

}

delete_user_directories() {
  USERNAME="$1"
  rm -R "/home/$USERNAME"
}

update_jail() {
  BASEJAIL="$1"

  # User in the jail
}

