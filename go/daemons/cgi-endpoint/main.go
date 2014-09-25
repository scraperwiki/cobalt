package main

import (
	"fmt"
	"io"
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
	// "github.com/phyber/negroni-gzip/gzip"
	"github.com/stretchr/graceful"
)

var (
	cobaltHome   = "/var/lib/cobalt/home" // Location of boxes outside chroot
	boxHome      = "/home"                // Location of $HOME inside one chroot
	globalCGI    = "/tools/global-cgi"    // Location of global CGI scripts
	checkToken   = "http://localhost:23423"
	inProduction = false // Running in production
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
	if os.Getenv("COBALT_CHECKTOKEN") != "" {
		checkToken = os.Getenv("COBALT_CHECKTOKEN")
	}

	inProduction = os.Getenv("SCRAPERWIKI_ENV") == "production"
}

// Split the string into the bit which identifies the box and task
// ({boxname}, {publishToken}, {task e.g cgi-bin}) and (script path to invoke)
func GetTarget(r *http.Request) (prefix, target string) {
	result := strings.SplitN(r.URL.Path, "/", 5)
	if len(result) != 5 {
		log.Panic("Request URI not of the right form: %q", r.URL.RequestURI())
	}
	prefix = strings.Join(result[:4], "/")
	target = "/" + result[4]
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

// Note: this assumes running in a context with the UID or GID of the
// user/group of the file. This is good enough for us.
// In an ideal world the file would just be invoked, but it's not possible
// to do this here, since we don't want to run the whole CGI handler repeatedly
// for every possible file, since it's rather expensive.
func isExecutable(mode os.FileMode) bool {
	return int(mode&0111) != 0
}

// Can we execute this as a CGI handler?
// ("Does it exist for our purposes")
func Exists(path string) bool {
	// log.Println("Tried", path)
	s, err := os.Stat(path)
	if err == nil && !s.IsDir() {
		return isExecutable(s.Mode())
	}
	return false
}

// Locate `target` in `users` box, returning the resulting path and true if
// found. It also searches for matching default scripts, and in the
// /tool/cgi-bin directory, and in the /tool/globals directory.
func FindCgiScript(user, target string) (fullpath, uri string, ok bool) {
	var thisOutsideChrootHome = path.Join(cobaltHome, user)

	// Path to $HOME inside box doesn't contain $USER in production.
	var thisBoxHome = boxHome
	if !inProduction {
		// If we're in a production environment, then we find home at `boxHome`,
		// otherwise it's at `{boxHome}/{username}`.
		thisBoxHome = path.Join(boxHome, user)
	}

	// Search for a script at {root}/{target}, then look for matching scripts
	// living in directories named `default`.
	// Returns the path to the script to invoke relative to `root` when found,
	// which may be a script named `default`.
	lookForScript := func(root, target string) (uri string, ok bool) {
		ok = Exists(path.Join(root, target))
		if ok {
			return target, true
		}
		for target != "/" {
			uri := path.Join(target, "default")
			ok = Exists(path.Join(root, uri))
			if ok {
				return uri, true
			}
			target = path.Dir(target)
		}
		return "", false
	}

	roots := []struct {
		outsideChrootBase, base, place string
	}{
		{thisOutsideChrootHome, thisBoxHome, "cgi-bin"},
		{thisOutsideChrootHome, thisBoxHome, "tool/cgi-bin"},
		{globalCGI, globalCGI, "cgi-bin"},
	}

	for _, root := range roots {
		uri, ok := lookForScript(path.Join(root.outsideChrootBase, root.place), target)
		if ok {
			return path.Join(root.base, root.place, uri), uri, ok
		}
	}

	return "", "", false
}

func HandleCGI(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	user := vars["box"]
	prefix, target := GetTarget(r)

	// Prefix contains /{boxname}/{boxToken}
	// scriptUri contains /cgi-bin/foo.

	scriptPath, scriptUri, ok := FindCgiScript(user, target)
	if !ok {
		http.NotFound(w, r)
		return
	}
	// log.Printf("%v = FindCgiScript(%v) -> %v", ok, target, scriptPath)

	var cgipath = ""
	var cgiargs = []string{}

	// We have to use shell because we're using su to become the right user.
	// We also can't specify these varibles directly because they're
	// overwritten by the CGI handler.
	const code = `
		# SCRIPT_NAME is the URI to the script itself (may be equal to the
		# location of "default")
		export SCRIPT_NAME="$1"; shift
		# These two are the full path of the script being invoked
		export SCRIPT_FILENAME="$1"
		export SCRIPT_PATH="$1"
		cd "$(dirname "$SCRIPT_PATH")"
		exec "$@"
	`

	args := []string{path.Join(prefix, scriptUri), scriptPath}

	if inProduction {
		cgipath = "/bin/su"
		cgiargs = append([]string{"--shell=/bin/sh", "-c", code, user, "--", "-sh"}, args...)
	} else {
		// sh doesn't take `user`, nor `$0`.
		cgipath = "/bin/sh"
		cgiargs = append([]string{"-c", code, "--"}, args...)
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
			"SERVER_SOFTWARE=github.com/scraperwiki/cobalt/go/daemons/cgi-endpoint",
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

func tokenVerifier(rw http.ResponseWriter, r *http.Request, next http.HandlerFunc) {
	vars := mux.Vars(r)

	if checkToken == "off" {
		next(rw, r)
		return
	}

	endpoint := checkToken + "/" + path.Join(vars["box"], vars["publishToken"])
	resp, err := http.Get(endpoint)
	if err != nil {
		log.Println("Unable to access", endpoint, "err =", err)
		http.Error(rw, "503 Service Unavailable", http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		rw.WriteHeader(resp.StatusCode)
		// Discard error.
		_, _ = io.Copy(rw, resp.Body)
		return
	}

	next(rw, r)
}

// Wrap the given handler with a token verifier
func WrapTokenVerifier(handler http.Handler) http.Handler {

	middleware := negroni.New()
	middleware.Use(negroni.HandlerFunc(tokenVerifier))
	middleware.UseHandler(handler)

	top := mux.NewRouter()
	top.PathPrefix("/{box}/{publishToken}/").Handler(middleware)

	return top
}

func NewHandler() http.Handler {

	box := mux.NewRouter().PathPrefix("/{box}/{publishToken}/").Subrouter()

	box.PathPrefix("/cgi-bin/").HandlerFunc(HandleCGI)
	box.PathPrefix("/http/").HandlerFunc(HandleHTTP)

	n := negroni.Classic()
	// n.Use(gzip.Gzip(1))
	n.UseHandler(WrapTokenVerifier(box))

	return n
}

func main() {

	log.Println("COBALT_HOME =", cobaltHome)
	log.Println("COBALT_BOX_HOME =", boxHome)
	log.Println("COBALT_GLOBAL_CGI =", globalCGI)
	log.Println("COBALT_CHECKTOKEN =", checkToken)
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
