package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path"
	"strings"
	"time"

	// We use our own fork to get the connection termination behaviour
	// we need.
	// "net/http/cgi"
	"github.com/scraperwiki/cobalt/go/daemons/cgi-endpoint/go/cgi"

	"github.com/codegangsta/negroni"
	"github.com/gorilla/mux"
	"github.com/stretchr/graceful"
)

var (
	cobaltHome   = "/var/lib/cobalt/home" // Location of boxes outside chroot
	boxHome      = "/home"                // Location of $HOME inside one chroot
	globalCGI    = "/tools/global-cgi"    // Location of global CGI scripts
	inProduction = false                  // Running in production
)

func init() {
	if os.Getenv("COBALT_HOME") != "" {
		cobaltHome = os.Getenv("COBALT_HOME")
	}
	if os.Getenv("COBALT_BOX_HOME") != "" {
		boxHome = os.Getenv("COBALT_BOX_HOME")
	}
	if os.Getenv("COBALT_GLOBAL_CGI") != "" {
		globalCGI = os.Getenv("COBALT_GLOBAL_CGI")
	}

	inProduction = os.Getenv("SCRAPERWIKI_ENV") == "production"
}

// This setup prevents shell injection.
const code = `
	# set -x

	# Children don't inherit these.
	declare +x COBALT_HOME COBALT_BOX_HOME COBALT_GLOBAL_CGI SCRAPERWIKI_ENV

	# Intentionally inherited in case anyone wants to know.
	declare -x COBALT_URI_BASE

	# This code runs inside a chroot in production environments.

	# Try to invoke the specified CGI script if it exists, is executable,
	# is not a directory. On success, exit this shell script immediately.

	try_invoke() {
		local base="$1"
		local dir="$2"
		local bin="$3"

		# Path with respect to http
		local uri="${dir}/${bin}"

		# Path on disk (inside chroot)
		local fullpath="${base}${uri}"

		if [ -x "${fullpath}" ] && [ ! -d "${fullpath}" ]; then
			export SCRIPT_NAME="${COBALT_URI_BASE}${uri}" SCRIPT_PATH="${fullpath}"
			cd "${base}/${dir}" && exec "${fullpath}"
			exit
		fi
	}

	try_cgi() {
		local base="$1"
		local dir="$2"
		local target="$3"

		try_invoke "${base}" "${dir}" "${target}"

		local test_path="${target}"

		# Progressively strip basename from ${test_path}, searching for a
		# .../default script that can be invoked.
		while :
		do
			try_invoke "${base}" "${dir}" "${test_path}/default"

			if [ "${test_path}" = "." ]; then
				break
			fi
			local test_path="$(dirname "${test_path}")"
		done
	}

	# Try user's /home/cgi-bin, then user's /home/tool/cgi-bin, then
	# finally the global ${COBALT_GLOBAL_CGI}/cgi-bin.

	# For each case, first try directly invoking it, then try and see if
	# a ./default script inside a directory should be ran.

	# The first hit to succeed causes this script to immediately exit.

	try_cgi "${COBALT_BOX_HOME}" "/cgi-bin" "$1"
	try_cgi "${COBALT_BOX_HOME}" "/tool/cgi-bin" "$1"
	try_cgi "${COBALT_GLOBAL_CGI}" "/cgi-bin" "$1"

	echo Status: 404 Not Found
	echo Content-Type: text/plain
	echo
	echo 404 Not Found
`

// Split the string into the bit which identifies the box and task
// ({boxname}, {publishToken}, {task e.g cgi-bin}) and (script path to invoke)
func GetTarget(r *http.Request) (prefix, target string) {
	result := strings.SplitAfterN(r.URL.Path, "/", 5)
	if len(result) != 5 {
		log.Panic("Request URI not of the right form: %q", r.URL.RequestURI())
	}
	prefix = strings.Join(result[:4], "/")
	target = result[4]
	log.Println("TARGET: ", target)
	return
}

func HandleHTTP(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	user := vars["box"]

	prefix, _ := GetTarget(r)

	root := http.Dir(path.Join(cobaltHome, user, "http"))

	staticHandler := http.StripPrefix(prefix, http.FileServer(root))
	staticHandler.ServeHTTP(w, r)
}

func HandleCGI(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	user := vars["box"]

	_, target := GetTarget(r)

	cgipath := "sh"
	cgiargs := []string{"-c", code, user, target}

	if inProduction {
		cgipath = "/bin/su"
		cgiargs = append([]string{"--shell=/bin/bash"}, cgiargs...)
	}

	var thisBoxHome = boxHome
	if !inProduction {
		// If we're in a production environment, then we find home at `boxHome`,
		// otherwise it's at `{boxHome}/{username}`.
		thisBoxHome = path.Join(thisBoxHome, user)
	}

	// on Dir: In the usual case where we're su'ing into a box, setting Dir has
	// no effect because the PAM chroot module changes the current directory
	// (to be / in the box's chrooted environment).
	// on $HOME: The cgi module only sets certain environment variables, and
	// leaves HOME unset. We set the directory within the command invoked.
	handler := &cgi.Handler{
		Path: cgipath,
		Args: cgiargs,
		Env: []string{
			fmt.Sprint("COBALT_URI_BASE=/", vars["box"], "/", vars["publishToken"]),
			"SERVER_SOFTWARE=github.com/scraperwiki/cobalt/go/daemons/cgi-endpoint",
			"COBALT_BOX_HOME=" + thisBoxHome,
			"COBALT_GLOBAL_CGI=" + globalCGI,
		}}

	handler.ServeHTTP(w, r)
}

func Listen(host, port string) (l net.Listener, err error) {
	if len(port) == 0 {
		err = fmt.Errorf("Bad listen address, please set PORT and optionally HOST")
		return
	}
	if host == "unix" {
		l, err = net.Listen("unix", port)
	} else {
		addr := host + ":" + port
		l, err = net.Listen("tcp", addr)
	}
	return
}

func NewHandler() http.Handler {
	router := mux.NewRouter()

	box := router.PathPrefix("/{box}/{publishToken}/").Subrouter()

	box.PathPrefix("/cgi-bin/").HandlerFunc(HandleCGI)
	box.PathPrefix("/http/").HandlerFunc(HandleHTTP)

	n := negroni.Classic()
	n.UseHandler(router)

	return n
}

func main() {

	log.Println("COBALT_HOME =", cobaltHome)
	log.Println("COBALT_BOX_HOME =", boxHome)
	log.Println("COBALT_GLOBAL_CGI =", globalCGI)
	log.Println("Production Environment =", inProduction)

	l, err := Listen(os.Getenv("HOST"), os.Getenv("PORT"))
	if err != nil {
		log.Fatalln("Error listening:", err)
	}
	defer l.Close()

	log.Printf("Listening on %s:%s", os.Getenv("HOST"), os.Getenv("PORT"))

	s := &http.Server{Handler: NewHandler()}

	// Graceful shutdown servers immediately stop listening on CTRL-C, but give
	// ongoing connections a  chance to finish before terminating.
	const gracefulShutdownTime = 5 * time.Second
	graceful.Serve(s, l, gracefulShutdownTime)
}
