package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/user"
	"runtime"
	"syscall"
)

const databoxGid = 10000

func isDataboxUser(userName string) (bool, error) {
	u, err := user.Lookup(userName)
	if err != nil {
		return false, err
	}
	return u.Gid == fmt.Sprint(databoxGid), err
}

func main() {
	if len(os.Args) < 2 {
		log.Fatalln("Usage: asbox <user> <shell command> [args...]")
	}

	user, args := os.Args[1], os.Args[2:]
	databox, err := isDataboxUser(user)
	if err != nil {
		log.Fatalln("Unable to determine if", user, "is a databox user:", err)
	}

	if !databox {
		log.Fatalln(user, "is not a databox user")
	}

	binary, err := exec.LookPath("su")
	if err != nil {
		log.Fatalln("Unable to find 'su':", err)
	}

	runtime.LockOSThread()
	err = syscall.Setuid(0)
	if err != nil {
		log.Fatalln("Unable to setuid")
	}

	args = append([]string{"su", "-", user, "-c", args[0], "--"}, args[1:]...)
	err = syscall.Exec(binary, args, os.Environ())
	log.Fatalln("Failed to exec:", err)
}
