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
	cgipath := lastComponent
	cgiargs := []string{}
	user := "drj"
	if os.Getuid() == 0 {
		// insert su
		cgicmd := strings.Join([]string{".", cgipath}, "/")
		cgiargs = []string{"-c", cgicmd, user}
		log.Print(cgiargs)
		var err error
		cgipath, err = exec.LookPath("su")
		if err != nil {
			log.Panic(err)
		}
	}
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
