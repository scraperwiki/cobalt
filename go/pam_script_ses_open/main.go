package main

import (
	"fmt"
	"io/ioutil"
	logpkg "log"
	"log/syslog"
	"os"
	"os/exec"
	"os/user"
	"path"
	"regexp"
	"runtime"
	"syscall"
	"time"

	"github.com/dotcloud/docker/pkg/mount"
)

// Must be true everywhere.
const databoxGid = 10000

var pamUser = os.Getenv("PAM_USER")

var log *logpkg.Logger

func init() {
	os.Args[0] = "PSSO"
	log, _ = syslog.NewLogger(syslog.LOG_WARNING|syslog.LOG_AUTH, 0)
}

func Fatal(first string, args ...interface{}) {
	// TODO(pwaller): send to syslog?
	log.Fatalf("pam script: "+first, args...)
}

func isDataboxUser() bool {
	u, err := user.Lookup(pamUser)
	if err != nil {
		Fatal("Failed to obtain passwd entry for %q", pamUser)
	}
	return u.Gid == fmt.Sprint(databoxGid)
}

func initMounts() {
	home := path.Join("/var/lib/cobalt/home/", pamUser)

	mounts := []struct{ src, tgt string }{
		{"/opt/basejail", "/jail"},
		{"/dev", "/jail/dev"},
		{"/dev/pts", "/jail/dev/pts"},
		{"/proc", "/jail/proc"},
		{"/var/spool/cron/crontabs", "/jail/var/spool/cron/crontabs"},
		{"/var/lib/extrausers", "/jail/var/lib/extrausers"},
		{home, "/jail/home"},
	}

	for _, m := range mounts {
		// Note the use of recursive bind mounts.
		// We could avoid some mounts by just arranging that /opt/basejail
		// already has most of the mounts.
		err := mount.Mount(m.src, m.tgt, "", "rbind")
		if err != nil {
			log.Fatalf("pamscript: Failed to mount %s -> %s: %q", m.src, m.tgt, err)
		}
	}
}

func cgcreate() error {
	args := []string{"-t", pamUser, "-g", "memory,cpu,cpuacct:" + pamUser}
	cmd := exec.Command("cgcreate", args...)
	return cmd.Run()
}

func initCgroup() {
	_, err := exec.LookPath("cgcreate")
	if err != nil {
		// cgroups isn't installed on this machine, NOOP.
		return
	}

	if _, err := os.Stat(path.Join("/sys/fs/cgroup/cpu", pamUser)); err != nil {
		err = cgcreate()
		if err != nil {
			Fatal("Failed to create cgroup")
		}
	}

	// 512MiB
	const memoryLimit = 512 * 1024 * 1024

	f := path.Join("/sys/fs/cgroup/memory", pamUser, "/memory.limit_in_bytes")
	err = ioutil.WriteFile(f, []byte(fmt.Sprint(memoryLimit)), 0)
	if err != nil {
		Fatal("Failed to write", f, ":", err)
	}

	// echo $MemoryLimit > /sys/fs/cgroup/memory/$PAM_USER/memory.limit_in_bytes

	// TODO(pwaller): do we want this? Maybe? Is there some other way we can give
	// system things priority?

	// # CPU share is form of priority. By specifying a low number here, we
	// # ensure that important system services get a higher share of the CPU
	// # and thus remain responsive.
	// Priority=12
	// echo $Priority > /sys/fs/cgroup/cpu/$PAM_USER/cpu.shares

	// Put the owning process (usually the "su -l" or cron child process)
	// into the cgroup (and therefore all of its future children)

	files := []string{
		path.Join("/sys/fs/cgroup/cpu", pamUser, "/tasks"),
		path.Join("/sys/fs/cgroup/memory", pamUser, "/tasks"),
		path.Join("/sys/fs/cgroup/cpuacct", pamUser, "/tasks"),
	}

	parentPid := []byte(fmt.Sprint(os.Getppid()))
	for _, f := range files {
		err = ioutil.WriteFile(f, parentPid, 0)
		if err != nil {
			Fatal("Failed to write", f, ":", err)
		}
	}
}

func verifyMountNamespace() {
	// if [[ "$(readlink /proc/1/ns/mnt)" == "$(readlink /proc/self/ns/mnt)" ]]; then
	initMountNS, err := os.Readlink("/proc/1/ns/mnt")
	if err != nil {
		Fatal("Unable to readlink(/proc/1/ns/mnt). Aborting.")
	}
	myMountNS, err := os.Readlink("/proc/self/ns/mnt")
	if err != nil {
		Fatal("Unable to readlink(/proc/self/ns/mnt). Aborting.")
	}
	if initMountNS == myMountNS {
		Fatal("Not in mount namespace. Abort.")
	}
}

func main() {

	syscall.Close(2)
	syscall.Open("/var/log/pam_script_ses_open.err", syscall.O_CREAT|syscall.O_APPEND|syscall.O_WRONLY, 0660)

	go func() {
		time.Sleep(10 * time.Second)

		pid := os.Getpid()

		log.Println(pid, "Terminated after timeout")

		buf := make([]byte, 1024*1024)
		amt := runtime.Stack(buf, true)
		stack := buf[:amt]

		r := regexp.MustCompile("(goroutine.*)\n.*\n\\s+(.*)")

		matches := r.FindAllSubmatch(stack, -1)

		for _, m := range matches {
			log.Printf("%d %s %s\n", pid, m[1], m[2])
		}

		os.Exit(1)
	}()

	// Voodoo: Ensure that code runs in the same thread with the high priority.
	// <pwaller> I did this because you can see threads that don't have the
	// highest priority. Hopefully this helps?
	runtime.LockOSThread()

	me := os.Getpid()
	const HIGHEST_PRIORITY = -20
	err := syscall.Setpriority(syscall.PRIO_PROCESS, me, HIGHEST_PRIORITY)
	if err != nil {
		log.Println("Setpriority() ->", err)
	}

	start := time.Now()
	defer func() {
		// Include the time in milliseconds.
		timeMillis := time.Since(start).Seconds() * 1000
		s := fmt.Sprintf("$PAM_USER $PAM_SERVICE %f $PAM_RHOST", timeMillis)
		log.Println(os.ExpandEnv(s))
	}()

	if !isDataboxUser() {
		log.Println("Skip non-databox user")
		// skip non-databox login
		return
	}

	if pamUser == "" {
		Fatal("PAM_USER not set. Abort.")
	}

	verifyMountNamespace()

	initCgroup()
	initMounts()
}
