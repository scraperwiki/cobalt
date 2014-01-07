package main

import (
	"flag"
	"log"
	"net"
	"net/http"
	"net/http/cgi"
	"net/http/fcgi"
	"os"
	"os/exec"
	"os/signal"
	"strings"
)

var (
	socketPath  = flag.String("socketpath", "/var/run/gobalt.socket", "path to listening socket")
	socketUser  = flag.String("socketuser", "www-data", "owner for socket")
	socketGroup = flag.String("socketgroup", "www-data", "owner for socket")
)

type Handler struct {
}

func (h *Handler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	log.Println("Inbound request for", req.URL.String())
	url := req.URL
	path := url.Path
	slice := strings.Split(path, "/")
	command := strings.Join(slice[4:], "/")
	// We either execute "sh -c something" (when not root),
	// or "su -c something" (when root).
	cgipath := "sh"
	user, ok := req.Header["Cobalt-User"]
	if !ok {
		user = []string{"databox"}
	}
	// This setup prevents shell injection.
	cgiargs := []string{"-c", "cd /home/cgi-bin && /home/cgi-bin/\"$1\"", user[0], "--", "-", command}
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
	// We set the directory within the command.
	handler := &cgi.Handler{
		Path: cgipath,
		Args: cgiargs,
		Env: []string{
			"SCRIPT_NAME=" + path,
			"SCRIPT_FILENAME=" + "/home/cgi-bin/" + command,
			"SERVER_SOFTWARE=github.com/scraperwiki/gobalt",
		}}
	handler.ServeHTTP(rw, req)
}

func main() {
	flag.Parse()
	_ = os.Remove(*socketPath)
	l, err := net.Listen("unix", *socketPath)
	if err != nil {
		log.Panic(err)
	}
	defer l.Close()
	err = exec.Command("chown", *socketUser+":"+*socketGroup, *socketPath).Run()
	if err != nil {
		log.Panic(err)
	}
	handler := &Handler{}
	log.Println("Serving on", *socketPath)

	go func() {
		err = fcgi.Serve(l, handler)
		if err != nil {
			log.Panic(err)
		}
	}()

	sig := make(chan os.Signal)
	signal.Notify(sig, os.Interrupt)
	<-sig
}
