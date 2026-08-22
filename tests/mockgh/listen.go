package main

import (
	"net"
)

// listen is split out so main can print its readiness line only after the
// socket is actually bound. Printing before Listen would let the orchestrating
// script race ahead and get "connection refused".
func listen(addr string) (net.Listener, error) {
	return net.Listen("tcp", addr)
}
