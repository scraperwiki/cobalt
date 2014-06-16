#! /bin/bash


FIXTURES=$PWD/fixtures

go build &&

PORT=3000 \
COBALT_HOME=$FIXTURES/homes \
COBALT_BOX_HOME=$FIXTURES/homes \
COBALT_GLOBAL_CGI=$FIXTURES/global \
COBALT_CHECKTOKEN=off \
./cgi-endpoint
