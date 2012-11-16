# ScraperWiki Cobalt #

Cobalt is a ScraperWiki service where people can run code on the
internet in
a sandboxed environment.

### Dependencies ###

5 git repositories are needed (cobalt, lithium, swops, swops-secret).
They should be cloned side-by-side.

    git clone git@github.com:scraperwiki/swops-secret.git
    git clone git@github.com:scraperwiki/lithium.git
    git clone git@github.com:scraperwiki/cobalt.git
    git clone git@github.com:scraperwiki/swops.git

You can do this from a directory that isn't your home directory, but you'll need to
symlink the keyfile in swops-secret and set permissions:

    mkdir ~/swops-secret
    ln swops-secret/id_dsa ~/swops-secret/id_dsa
    chmod 0600 ~/swops-secret/id_dsa
    
Lithium and Cobalt both have their own dependencies for Node
packages. You'll need to install them when you first clone, and then
every now and then as the dependencies change.  The *first* time
you do this you will need the '-f' option to npm because the
linode.api Node.js package incorrectly asserts a dependency on
Node 0.4.x (but in fact works fine with later versions):

    for d in lithium cobalt; do ( cd $d; npm -f install ) done
    
Running this when you don't need to is fine – it doesn't take very long.

### Coming Back ###

Don't forget to sync your repositories:

    for d in lithium cobalt swops swops-secret; do ( cd $d; git pull ) done

(you need to 'npm install' every now and then too, but you won't
generally need to use the '-f' option (see above))

### Getting Started ###

You need to set up the environment and so on:
    
    cd lithium
    . ../swops-secret/keys.sh
    . ./activate

swops-secret actually needs to be in `$HOME`. Do this to make sure it is.

    cd ../swops-secret
    ./install.sh

### Running Cobalt ###

To run cobalt locally:

    cd cobalt
    . ./activate
    coffee code/serv.coffee

You can start and stop Cobalt on an Ubuntu server using upstart:

    start cobalt
    stop cobalt

### Running Cobalt Tests ###
To run the unit tests (note that cobalt must be running):

    cd cobalt
    . ./activate
    mocha

To get the integration server to pull the most recent changes:

    li sh boxecutor-int-test-0 "cd /opt/cobalt && git pull && service cobalt restart"

and to run the integration tests:
    
    mocha integration_test

integration_test/cobalt.coffee has the host name that the integration tests
are run on hardwired into it. Its key is in swops-secret.

