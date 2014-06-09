package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strings"
	"time"

	// "net/http/cgi"
	"github.com/scraperwiki/cobalt/go/daemons/cgi-endpoint/go/cgi"

	"github.com/codegangsta/negroni"
	"github.com/gorilla/mux"
	"github.com/stretchr/graceful"
)

var (
	cobaltHome = "/var/lib/cobalt/home" // Location of boxes outside chroot
	boxHome    = "/home"                // Location of $HOME inside one chroot
	globalCGI  = "/tools/global-cgi"    // Location of global CGI scripts
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
}

// This setup prevents shell injection.
// Try first /home/cgi-bin, then /home/tool/cgi-bin
const code = `
	set -x
	try_invoke() {
		local dir="$1"
		local bin="$2"
		local fullpath="${dir}/${bin}"
		if [ -x "${fullpath}" ] && [ ! -d "${fullpath}" ]; then
			cd "${dir}" && SCRIPT_PATH="${fullpath}" exec "${fullpath}"
			exit
		fi
	}

	# TODO(pwaller): set SCRIPT_FILENAME correctly
	#invoke() {
		#SCRIPT_FILENAME="$1" "$1"
	#}
	# printf ".%s.\n" "$@" 1>&2
	# echo "$@"

	try_invoke "${COBALT_BOX_HOME}/cgi-bin" "$1"
	try_invoke "${COBALT_BOX_HOME}/tool/cgi-bin" "$1"
	try_invoke "${COBALT_GLOBAL_CGI}/" "$1"

	P="$1"

	while :
	do
		try_invoke "${COBALT_BOX_HOME}/cgi-bin" "${P}/default"
		try_invoke "${COBALT_BOX_HOME}/tool/cgi-bin" "${P}/default"
		# if [ -x "${COBALT_BOX_HOME}/cgi-bin/$P/default" ]; then
		# 	cd ${COBALT_BOX_HOME}/cgi-bin && ${COBALT_BOX_HOME}/cgi-bin/"$P"/default
		# 	exit 0
		# fi
		# if [ -x "${COBALT_BOX_HOME}/tool/cgi-bin/$P/default" ]; then
		# 	cd ${COBALT_BOX_HOME}/tool/cgi-bin && ${COBALT_BOX_HOME}/tool/cgi-bin/"$P"/default
		# 	exit 0
		# fi
		if [ "$P" = "." ]; then
			break
		fi
		P="$(dirname "$P")"

	done

	echo Status: 404 Not Found
	echo Content-Type: text/plain
	echo
	echo 404 Not Found
`

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
	if os.Getuid() == 0 {
		cgipath = "su"
	}
	var err error
	cgipath, err = exec.LookPath(cgipath)
	if err != nil {
		log.Panic(err)
	}
	// on Dir: In the usual case where we're su'ing into a
	// box, setting Dir has no effect because the PAM
	// chroot module changes the current directory
	// (to be / in the box's chrooted environment).
	// on $HOME: The cgi module only sets certain
	// environment variables, and leaves HOME unset.
	// We set the directory within the command.

	if boxHome == cobaltHome {
		// TODO(pwaller)
		// If they're the same, we're probably not in a chroot.
		boxHome = path.Join(boxHome, user)
	}
	handler := &cgi.Handler{
		Path: cgipath,
		Args: cgiargs,
		Env: []string{
			// "SCRIPT_FILENAME=" + "/home/cgi-bin/" + target,
			"SERVER_SOFTWARE=github.com/scraperwiki/cobalt/go/daemons/cgi-endpoint",
			"COBALT_BOX_HOME=" + boxHome,
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

func main() {

	l, err := Listen(os.Getenv("HOST"), os.Getenv("PORT"))
	if err != nil {
		log.Fatalln("Error listening:", err)
	}
	defer l.Close()

	router := mux.NewRouter()

	box := router.PathPrefix("/{box}/{publishToken}/").Subrouter()

	box.PathPrefix("/cgi-bin/").HandlerFunc(HandleCGI)
	box.PathPrefix("/http/").HandlerFunc(HandleHTTP)

	n := negroni.Classic()
	n.UseHandler(router)

	s := &http.Server{
		Handler: n,
	}

	const gracefulShutdownTime = 5 * time.Second
	graceful.Serve(s, l, gracefulShutdownTime)
}
