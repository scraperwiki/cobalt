package main

import (
	"log"
	"net"
	"net/http"
	"net/http/fcgi"
	"os"
)

type Handler struct {
}

func (h *Handler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	rw.Header()["foo"] = []string{"ia"}
	rw.Write([]byte("Hello World!\n"))
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
