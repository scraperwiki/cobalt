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

Integration Tests.

You usually need to give the integration server the most recent code.
the 029 hook will pull it from your local disk:

    li runhook li runhook boxecutor-int-test-0 boxecutor-thin 029_copy_cobalt_from_local.l.sh
    # And restart cobalt
    li sh boxecutor-int-test-0 "service cobalt restart"

Or if you like you can pull from github, but this is less good, because
you must have pushed to github first:

    li sh boxecutor-int-test-0 "cd /opt/cobalt && git pull && service cobalt restart"

In any case to run the integration tests:

    mocha integration_test

The host that is used for the integration test defaults to something
hardwired in the source cod (integration_test/cobalt.coffee),
but can be overridden with an environment variable:

    COBALT_INTEGRATION_TEST_SERVER=boxecutor-dev-1.scraperwiki.net mocha integration_test/

