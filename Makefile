# Copyright 2011 The Go Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

include ../../../../Make.inc

TARG=net/http/cgi
GOFILES=\
	child.go\
	host.go\

include ../../../../Make.pkg
