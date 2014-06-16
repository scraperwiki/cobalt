echo "-- ENV:"
curl localhost:3000/a/token/cgi-bin/env.sh?foobarbaz
echo

echo "-- DATE:"
curl localhost:3000/a/token/cgi-bin/date.sh
echo

echo "-- /home-dir -> /home-dir/default:"
curl localhost:3000/a/token/cgi-bin/home-dir
echo

echo "-- /home-dir/foo/bar -> /home-dir/default:"
curl localhost:3000/a/token/cgi-bin/home-dir/foo/bar
echo

echo "-- POST /home-dir/foo/bar -> /home-dir/default:"
curl -d 'HELLO' localhost:3000/a/token/cgi-bin/home-dir/foo/bar
echo

echo "-- /cgi-bin/tool-script (finds /home/tool/cgi-bin/tool-script)"
curl localhost:3000/a/token/cgi-bin/tool-script
echo

echo "-- /cgi-bin/tool-dir (finds /home/tool/cgi-bin/tool-dir/default)"
curl localhost:3000/a/token/cgi-bin/tool-dir/foo/bar/baz
echo

echo "-- /cgi-bin/global-script (finds /tools/global-cgi/cgi-bin/tool-script)"
curl localhost:3000/a/token/cgi-bin/global-script
echo

echo "-- /cgi-bin/tool-dir (finds /tools/global-cgi/cgi-bin/tool-dir/default)"
curl localhost:3000/a/token/cgi-bin/global-dir/foo/bar/baz
echo

echo "-- /cgi-bin/this-is-a-404-error"
curl localhost:3000/a/token/cgi-bin/this-is-a-404-error
