#! /usr/bin/env bash

D=$(date +%Y%m%d)

go build -v -o bin/scraperwiki-check-token-$D ./daemons/check-token
go build -v -o bin/scraperwiki-ssh-keys-$D ./daemons/ssh-keys
go build -v -o bin/scraperwiki-generate-extrausers-$D ./generate-extrausers

echo "Binaries placed in ./bin"