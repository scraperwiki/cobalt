package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/dchest/safefile"
	"gopkg.in/v2/mgo"
	"gopkg.in/v2/mgo/bson"
)

var boxServer = flag.String("boxServer", "", "boxServer to generate for")

type Dataset struct {
	Box                string `bson:"box"`
	CreatorDisplayName string `bson:"creatorDisplayName"`
	CreatorShortName   string `bson:"creatorShortName"`
	DisplayName        string `bson:"displayName"`
	User               string `bson:"user"`
	Tool               string `bson:"tool"`
	State              string `bson:"state"`
	BoxServer          string `bson:"boxServer"`
	Views              []struct {
		Box       string `bson:"box"`
		BoxServer string `bson:"boxServer"`
	} `bson:"views"`
}

type User struct {
	ShortName   string   `bson:"shortName"`
	CanBeReally []string `bson:"canBeReally"`
	SshKeys     []string `bson:"sshKeys"`
}

type Box struct {
	Name   string   `bson:"name"`
	Server string   `bson:"server"`
	Uid    uint32   `bson:"uid"`
	Users  []string `bson:"users"`
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func GetDatabase() *mgo.Database {
	db_host := os.Getenv("CU_DB")
	if db_host == "" {
		log.Fatal("CU_DB environment variable required")
	}
	session, err := mgo.Dial(db_host)
	check(err)

	return session.DB("")
}

func main() {
	flag.Parse()
	defer func() {
		if err := recover(); err != nil {
			panic(err)
		}
	}()
	if *boxServer == "" {
		log.Fatal("boxServer parameter required")
	}

	db := GetDatabase()

	// Query deleted datasets
	deletedQuery := bson.M{
		"$and": []bson.M{
			bson.M{"state": "deleted"},
			bson.M{"boxServer": *boxServer}}}

	if *boxServer == "*" {
		deletedQuery = bson.M{"state": "deleted"}
	}

	// Query all deleted dataset box names along with the view box names
	q := db.C("datasets").Find(deletedQuery).Select(bson.M{})
	q = q.Select(bson.M{"box": 1, "views.box": 1, "views.boxServer": 1})

	var datasets []Dataset
	err := q.All(&datasets)
	check(err)

	// Build map of deleted boxes, looking through all dataset.Views
	badBoxes := map[string]struct{}{}
	for _, dataset := range datasets {
		badBoxes[dataset.Box] = struct{}{}
		for _, view := range dataset.Views {
			badBoxes[view.Box] = struct{}{}
		}
	}

	match := bson.M{"server": *boxServer}
	if *boxServer == "*" {
		match = bson.M{}
	}

	q = db.C("boxes").Find(match)
	q = q.Select(bson.M{"name": 1, "uid": 1})

	var boxes []Box
	err = q.All(&boxes)
	check(err)

	goodBoxes := []Box{}
	for _, box := range boxes {
		if _, deleted := badBoxes[box.Name]; deleted {
			continue
		}
		goodBoxes = append(goodBoxes, box)
	}

	passwd, err := safefile.Create("passwd", 0666)
	check(err)
	defer passwd.Close()
	for _, box := range boxes {
		fmt.Fprintf(passwd, "%v:x:%v:10000::/home:/bin/bash\n", box.Name, box.Uid)
	}

	shadow, err := safefile.Create("shadow", 0666)
	check(err)
	defer shadow.Close()
	for _, box := range boxes {
		fmt.Fprintf(shadow, "%v:x:15607:0:99999:7:::\n", box.Name)
	}

	err = passwd.Commit()
	check(err)
	err = shadow.Commit()
	check(err)

	log.Printf("Generated len(%v) passwd file (%v deleted)", len(goodBoxes), len(boxes)-len(goodBoxes))
}
