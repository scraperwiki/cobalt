cobalt: scraperwiki-start-cobalt
checktoken: scraperwiki-check-token
sshkeys: scraperwiki-sshkeys
cgiendpoint: SCRAPERWIKI_ENV=production PORT=61234 scraperwiki-cgi-endpoint
nginx: nginx
oidentd: pkill oidentd; exec oidentd --nosyslog --foreground
fcgiwrap: pkill fcgi; exec /usr/bin/spawn-fcgi -n -P /var/run/fcgiwrap.pid -F '20' -s '/var/run/fcgiwrap.socket' -u 'www-data' -U 'www-data' -g 'www-data' -G 'www-data' -- /usr/sbin/fcgiwrap -f
ssh: mkdir -p /var/run/sshd && exec /usr/sbin/sshd -D
mongo: rm -f $PWD/_data/*.lock; mongod --dbpath $PWD/_data --nojournal --noprealloc --quiet
