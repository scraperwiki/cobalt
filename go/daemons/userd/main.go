package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"os/user"
	"path"
	"strconv"
	"sync"

	"github.com/go-martini/martini"
	"github.com/martini-contrib/binding"

	group "github.com/proxypoke/group.go"
)

var (
	cobaltHome      = flag.String("cobaltHome", "/var/lib/cobalt/home", "Home directory")
	passwdDir       = flag.String("passwdDir", "/var/lib/extrausers", "Path to passwd file")
	targetGroupName = flag.String("targetGroup", "databox", "default group to add users to")
)

var passwdPath, shadowPath string

const (
	JSON_OK          = `{"status": "ok"}`
	JSON_ERROR       = `{"status": "error"}`
	JSON_STATUS_TIME = `{
	"status": "ok",
	"nSuccess": "%v"
	"lastSuccess": "%v",
	"sinceLastSuccess": "%v",
	"nFailure": "%v",
	"lastFailure": "%v",
	"sinceLastFailure": "%v",
}`
)

type User struct {
	Name string `form:"name" binding:"required"`
	Uid  int    `form:"uid" binding:"required"`
}

func AppendFile(filename, content string) error {
	fd, err := os.OpenFile(filename, os.O_WRONLY|os.O_APPEND, 0777)
	if err != nil {
		return err
	}
	defer fd.Close()

	n, err := fd.WriteString(content)
	if n != len(content) {
		return io.ErrShortWrite
	}

	return nil
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func NewUser(u User, status *Status, l *log.Logger, oneAtATime *sync.Mutex,
	params martini.Params) (result string) {

	defer func() {
		if err := recover(); err != nil {
			<-status.Failure
			log.Println("Panicked making user:", err)
			result = JSON_ERROR
		}
	}()

	oneAtATime.Lock()
	defer oneAtATime.Unlock()

	// user
	_, err := user.LookupId(fmt.Sprint(u.Uid))
	if _, isUnknownUserIdError := err.(user.UnknownUserIdError); !isUnknownUserIdError {
		panic(fmt.Sprint("User already exists or other error creating", u, ":", err))
	}

	targetGroup, err := group.Lookup(*targetGroupName)
	if err != nil {
		log.Println("Error looking up databox group: ", err)
		panic(err)
	}

	targetGroupGid, err := strconv.ParseInt(targetGroup.Gid, 10, 32)
	check(err)

	passwdLine := fmt.Sprintf("%s:x:%d:%d::/home:/bin/bash\n", u.Name, u.Uid, targetGroupGid)
	shadowLine := fmt.Sprintf("%s:x:15607:0:99999:7:::\n", u.Name)

	check(AppendFile(passwdPath, passwdLine))
	check(AppendFile(shadowPath, shadowLine))

	homeDir := path.Join(*cobaltHome, u.Name)

	// umask should mask out bits
	check(os.MkdirAll(homeDir, 0777))
	check(os.Chown(homeDir, u.Uid, int(targetGroupGid)))

	<-status.Success
	return JSON_OK
}

func main() {

	flag.Parse()

	passwdPath = path.Join(*passwdDir, "passwd")
	shadowPath = path.Join(*passwdDir, "shadow")

	m := martini.Classic()

	oneAtATime := new(sync.Mutex)
	m.Map(oneAtATime)

	status := NewStatus()
	m.Map(status)

	defer func() {
		// Print json status on exit
		log.Println((<-status.Read).Json())
	}()

	m.Post("/users/", binding.Bind(User{}), NewUser)

	// For testing success/fail mechanism
	m.Get("/success", func(status *Status) { <-status.Success })
	m.Get("/failure", func(status *Status) { <-status.Failure })

	// Reporting the status as json
	m.Get("/status", func(status *Status) string {
		return (<-status.Read).Json()
	})

	go m.Run()

	interrupt := make(chan os.Signal)
	signal.Notify(interrupt, os.Interrupt)
	<-interrupt
	log.Println("SIGINT")
}
