package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"labix.org/v2/mgo"
	"labix.org/v2/mgo/bson"
	"github.com/dchest/safefile"
)

var boxName = flag.String("boxName", "", "boxServer to generate for")

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

	return session.DB("cu-live-eu")
}

func main() {
	flag.Parse()
	defer func() {
		if err := recover(); err != nil {
			panic(err)
		}
	}()
	if *boxName == "" {
		log.Fatal("boxName parameter required")
	}

	db := GetDatabase()

	// Query deleted datasets
	deletedQuery := bson.M{
		"$and": []bson.M{
			bson.M{"state": "deleted"},
			bson.M{"boxServer": *boxName}}}

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

	q = db.C("boxes").Find(bson.M{"server": *boxName})
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
