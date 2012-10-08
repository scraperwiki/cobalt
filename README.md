# ScraperWiki Cobalt #

Cobalt is a ScraperWiki service where people can run code on the
internet in
a sandboxed environment.

### Dependencies ###

3 git repositories are needed (cobalt, lithium, swops-secret).
They should be cloned side-by-side.  Pick a new directory if you want.

    git clone git@bitbucket.org:ScraperWiki/swops-secret.git
    git clone git@github.com:scraperwiki/lithium.git
    git clone git@github.com:scraperwiki/cobalt.git
    
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

    for d in lithium cobalt swops-secret; do ( cd $d; git pull ) done

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

### Using Lithium ###

Using lithium spends money.  Not much.

    li
    li list
    li create boxecutor
    li start boxecutor_1
    li deploy boxecutor_1

### Server States ###

                              .---------stop----------.
                              v                       |
    +-----+            +-------------+           +---------+
    |     | --create-> | not running | --start-> | running |
    +-----+            +-------------+           +---------+
       ^                      |                       |
       `-------------------destroy--------------------'
                            


