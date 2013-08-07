package main

import (
	"log"
	"net"
	"net/http"
	"net/http/cgi"
	"net/http/fcgi"
	"os"
	"strings"
)

type Handler struct {
}

func (h *Handler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	url := req.URL
	path := url.Path
	slice := strings.Split(path, "/")
	lastComponent := slice[len(slice)-1]
	handler := &cgi.Handler{Path: lastComponent}
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
