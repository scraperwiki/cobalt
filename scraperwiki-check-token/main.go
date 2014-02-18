package main

import (
	"flag"
	"net/http"
	"os"
	"strings"

	"labix.org/v2/mgo"
	"labix.org/v2/mgo/bson"
)

var dbName = flag.String("dbName", "cu-live-eu", "db to query for")

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

func GetDatabase() *mgo.Database {
	db_host := os.Getenv("CU_DB")
	session, err := mgo.Dial(db_host)
	check(err)

	return session.DB(*dbName)
}

func main() {
	flag.Parse()
	defer func() {
		if err := recover(); err != nil {
			panic(err)
		}
	}()

	db := GetDatabase()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Query boxes
		splitted := strings.SplitN(r.URL.Path[1:], "/", 2)
		if len(splitted) < 2 {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		validTokenQuery := bson.M{
			"$and": []bson.M{
				bson.M{"name": splitted[0]},
				bson.M{"boxJSON.publish_token": splitted[1]}}}

		n, err := db.C("boxes").Find(validTokenQuery).Count()
		check(err)
		if n == 0 {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	println("Listening...")
	err := http.ListenAndServe(":23423", nil)
	check(err)

}
