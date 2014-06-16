#! /usr/bin/env bash

D=$(date +%Y%m%d)

go get -v ./...

# Daemons
go build -v -o bin/scraperwiki-check-token-$D ./daemons/check-token
go build -v -o bin/scraperwiki-ssh-keys-$D ./daemons/ssh-keys
go build -v -o bin/scraperwiki-userd-$D ./daemons/userd
go build -v -o bin/scraperwiki-cgi-endpoint ./daemons/cgi-endpoint

# Binaries
go build -v -o bin/scraperwiki-generate-extrafiles-$D ./generate-extrafiles

echo "Binaries placed in ./bin"
