cobalt: scraperwiki-start-cobalt
gobalt: gobalt-fastcgi-server
nginx: nginx
oidentd: oidentd --nosyslog --foreground
fcgiwrap: /usr/bin/spawn-fcgi -n -P /var/run/fcgiwrap.pid -F '20' -s '/var/run/fcgiwrap.socket' -u 'www-data' -U 'www-data' -g 'www-data' -G 'www-data' -- /usr/sbin/fcgiwrap -f
