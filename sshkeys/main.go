package main

import (
	// "log"
	"fmt"
	"os"
	"strings"

	"labix.org/v2/mgo"
	"labix.org/v2/mgo/bson"
)

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func GetDatabase() *mgo.Database {
	db_host := os.Getenv("CU_DB_HOST")
	session, err := mgo.Dial(db_host)
	check(err)

	return session.DB("cu-live-eu")
}

type Dataset struct {
	CreatorDisplayName string `bson:"creatorDisplayName"`
	CreatorShortName   string `bson:"creatorShortName"`
	DisplayName        string `bson:"displayName"`
	User               string `bson:"user"`
	Tool               string `bson:"tool"`
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

func MatchAny(what string, values ...string) bson.M {
	var query []bson.M

	for _, value := range values {
		query = append(query, bson.M{what: value})
	}

	return bson.M{"$or": query}
}

func usersFromBox(db *mgo.Database, boxName string) (users []string) {

	x := db.C("boxes").Find(MatchAny("name", boxName))

	var result []Box

	err := x.All(&result)
	check(err)

	users = []string{}

	for _, b := range result {
		for _, user := range b.Users {
			users = append(users, user)
		}
	}
	return users
}

// Looking through canBeReally, find all SSH keys
func allKeysFromUsernames(db *mgo.Database, usernames []string) []string {
	seenSet := map[string]struct{}{}
	isSeen := func(u string) bool {
		_, ok := seenSet[u]
		return ok
	}
	extendSeenSet := func(us []string) {
		for _, u := range us {
			seenSet[u] = struct{}{}
		}
	}

	allKeys := []string{}

	for len(usernames) > 0 {
		toQuery := usernames
		extendSeenSet(toQuery)
		usernames = []string{}

		usersQuery := db.C("users").Find(MatchAny("shortName", toQuery...))
		// log.Println("users: ", toQuery)

		var matchingUsers []User
		usersQuery.All(&matchingUsers)
		for _, user := range matchingUsers {
			for _, nextUser := range user.CanBeReally {
				if !isSeen(nextUser) {
					usernames = append(usernames, nextUser)
				}
			}
			allKeys = append(allKeys, fmt.Sprintf("# From user:%s", user.ShortName))
			allKeys = append(allKeys, user.SshKeys...)
		}
	}

	return allKeys
}

func main() {
	defer func() {
		if err := recover(); err != nil {
			panic(err)
		}
	}()

	db := GetDatabase()

	usernames := usersFromBox(db, os.Args[1])

	// Looks through canBeReally
	keys := allKeysFromUsernames(db, usernames)

	for _, k := range keys {
		k = strings.Replace(k, "\n", "", -1)
		if !strings.HasPrefix(k, "ssh-") && !strings.HasPrefix(k, "#") {
			println("# NOT VAILD: ", k)
			continue
		}
		println(k)
	}

	// log.Println("Users: ", users)

	// us := db.C("users").Find(MatchAny("shortName", users...))

	// var matchingUsers []User
	// err := us.All(&matchingUsers)
	// check(err)

	// log.Printf("%#+v %v", matchingUsers, err)
}
