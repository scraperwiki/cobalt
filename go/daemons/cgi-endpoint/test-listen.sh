#! /bin/bash


go build

PORT=3000 COBALT_HOME=$PWD COBALT_BOX_HOME=$PWD/homes COBALT_GLOBAL_CGI=$PWD/global ./cgi-endpoint
