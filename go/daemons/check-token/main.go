package main

import (
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"labix.org/v2/mgo"
	"labix.org/v2/mgo/bson"
)

type Box struct {
	Name    string `bson:"name"`
	BoxJSON struct {
		PublishToken string `bson:"publish_token"`
	} `bson:"boxJSON"`
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

var ErrDbTimeout = errors.New("db took too long")

func main() {
	flag.Parse()
	defer func() {
		if err := recover(); err != nil {
			panic(err)
		}
	}()

	var session *mgo.Session
	var err error

	go func() {
		for session == nil {
			log.Println("Connecting to mongo..")

			session, err = mgo.Dial(os.Getenv("CU_DB"))

			if err != nil {
				if session != nil {
					session.Close()
					session = nil
				}
				log.Printf("Database connection failed (%q), retrying..", err)
				time.Sleep(10 * time.Second)
			}
		}
		log.Println("Connected to mongo.")
	}()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {

		// Query boxes
		splitted := strings.SplitN(r.URL.Path[1:], "/", 2)
		if len(splitted) < 2 {
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		if session == nil {
			log.Printf("%v StatusServiceUnavailable session == nil", splitted[0])
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}

		validTokenQuery := bson.M{
			"$and": []bson.M{
				bson.M{"name": splitted[0]},
				bson.M{"boxJSON.publish_token": splitted[1]}}}

		err := ErrDbTimeout
		var n int
		done := make(chan struct{})

		go func() {
			this_session := session.Copy()
			defer this_session.Close()

			db := this_session.DB("")

			n, err = db.C("boxes").Find(validTokenQuery).Count()
			close(done)
		}()

		select {
		case <-time.After(5 * time.Second):
		case <-done:
		}

		if err != nil {
			log.Printf("%v StatusServiceUnavailable %q", splitted[0], err)
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}

		if n == 0 {
			log.Printf("%v StatusForbidden", splitted[0])
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	println("Listening...")
	err = http.ListenAndServe(":23423", nil)
	check(err)

}
