package main

import (
	"log"
	"net"
	"net/http"
	"net/http/cgi"
	"net/http/fcgi"
	"os"
	"os/exec"
	"strings"
)

type Handler struct {
}

func (h *Handler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	url := req.URL
	path := url.Path
	slice := strings.Split(path, "/")
	lastComponent := slice[len(slice)-1]
	// We either execute "sh -c something" (when not root),
	// or "su -c something" (when root).
	cgipath := "sh"
	command := strings.Join([]string{".", lastComponent}, "/")
	// The usual case is that the URL is of the form:
	// https://premium.scraperwiki.com/febb3gq/rtgdf/http/thing
	// in which case the binary to run will be "home/http/thing",
	// and the PWD will be / in the box's chrooted
	// environment.
	// (RFC 3875/ says that the PWD will be the directory
	// containing the script, but that's quite tricky to achieve).
	if strings.Contains(path, "/http/") {
		slice = strings.SplitN(path, "/http/", 2)
		command = strings.Join([]string{"home/http/", slice[1]}, "")
	}
	user := "drj"
	cgiargs := []string{"-c", command, user}
	if os.Getuid() == 0 {
		cgipath = "su"
	}
	var err error
	cgipath, err = exec.LookPath(cgipath)
	if err != nil {
		log.Panic(err)
	}
	log.Print(cgipath, cgiargs)
	// on Dir: In the usual case where we're su'ing into a
	// box, setting Dir has no effect because the PAM
	// chroot module changes the current directory
	// (to be / in the box's chrooted environment).
	// on $HOME: The cgi module only sets certain
	// environment variables, and leaves HOME unset.
	handler := &cgi.Handler{Path: cgipath,
		Dir:  ".",
		Args: cgiargs}
	handler.ServeHTTP(rw, req)
}

func main() {
	l, err := net.Listen("tcp4", ":2000")
	if err != nil {
		log.Panic(err)
	}
	defer l.Close()
	handler := &Handler{}
	err = fcgi.Serve(l, handler)
	if err != nil {
		log.Panic(err)
	}
	os.Exit(0)
}
