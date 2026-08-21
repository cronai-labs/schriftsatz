module github.com/cronai-labs/schriftsatz

// The language version, not the toolchain patch. `go mod init` writes whatever
// is installed locally (1.26.6 here), which then refuses to build anywhere with
// an older patch release — the goreleaser container at 1.26.5, for one.
go 1.26
