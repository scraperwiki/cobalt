package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"labix.org/v2/mgo"
	"labix.org/v2/mgo/bson"
)

type Dataset struct {
	CreatorDisplayName string `bson:"creatorDisplayName"`
	CreatorShortName   string `bson:"creatorShortName"`
	DisplayName        string `bson:"displayName"`
	User               string `bson:"user"`
	Tool               string `bson:"tool"`
	State              string `bson:"state"`
	BoxServer          string `bson:"boxServer"`
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

func MatchAny(what string, values ...string) bson.M {
	var query []bson.M

	for _, value := range values {
		query = append(query, bson.M{what: value})
	}

	return bson.M{"$or": query}
}

// Obtain list of users allowed to access a box (directly specified in Box struct)
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

// Looking through canBeReally, find all SSH keys for all `usernames`.
// Makes as many queries as necessary according to the depth of the canBeReally
// tree, pruning duplicates.
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

		var matchingUsers []User
		err := db.C("users").Find(MatchAny("shortName", toQuery...)).All(&matchingUsers)
		if err != nil {
			log.Printf("Error querying users: %q -- us:%q", err, toQuery)
		}

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

// Get usernames of all staff
func getStaff(db *mgo.Database) []string {
	usersQ := db.C("users").Find(map[string]bool{"isStaff": true})

	var matchingUsers []User
	usersQ.All(&matchingUsers)

	users := []string{}
	for _, u := range matchingUsers {
		users = append(users, u.ShortName)
	}

	return users
}

// Merge two lists keeping only the uniques
func combineUsers(a, b []string) []string {
	both := append(a, b...)

	allowedUsers := map[string]struct{}{}
	for _, u := range both {
		allowedUsers[u] = struct{}{}
	}

	combined := []string{}
	for u := range allowedUsers {
		combined = append(combined, u)
	}
	return combined
}

// Get the list of all SSH keys allowed to access a box.
func getKeys(session *mgo.Session, boxname string) (boxUsers, usernames []string, keys string) {

	this_session := session.Clone()
	defer this_session.Close()

	db := this_session.DB("")

	staff := getStaff(db)
	boxUsers = usersFromBox(db, boxname)

	usernames = combineUsers(staff, boxUsers) // returned

	// Looks through `canBeReally`.
	keySlice := allKeysFromUsernames(db, usernames)

	for _, k := range keySlice {
		k = strings.Replace(k, "\n", "", -1)
		if !strings.HasPrefix(k, "ssh-") && !strings.HasPrefix(k, "#") {
			keys += "# NOT VAILD: "
		}
		keys += k + "\n"
	}

	return
}

// Serve sshkeys at http://:33845/{boxname}
func main() {
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
		u := r.URL.Path[1:]
		if session == nil {
			log.Printf("%v StatusServiceUnavailable session == nil", u)
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}

		boxUsers, allUsers, keys := getKeys(session, u)

		log.Printf("%s:%v:%q:%q", u, strings.Count(keys, "\n"), boxUsers, allUsers)
		fmt.Fprint(w, keys)
	})

	log.Println("Serving..")
	err = http.ListenAndServe("localhost:33845", nil)
	check(err)
}
