GOGCFLAGS := -gcflags=all=-e

# Let's not rebuild the parser if we don't have antlr available
ifeq ("", "$(strip $(shell which antlr))")
	antlr_sources :=
else
	antlr_sources := scripting/parser/herd_base_listener.go scripting/parser/herd_lexer.go scripting/parser/herd_listener.go scripting/parser/herd_parser.go
endif

# Let's not rebuild the protobuf code if we don't have protobuf available
ifeq ("", "$(strip $(shell which protoc))")
	protobuf_sources :=
else ifeq ("", "$(strip $(shell which protoc-gen-go))")
	protobuf_sources :=
else ifeq ("", "$(strip $(shell which protoc-gen-go-crpc))")
	protobuf_sources :=
else
	protobuf_sources = provider/plugin/common/plugin.pb.go provider/plugin/common/plugin_grpc.pb.go
endif

herd: go.mod go.sum *.go cmd/herd/*.go ssh/*.go scripting/*.go provider/*/*.go provider/plugin/common/*.go $(protobuf_sources) $(antlr_sources)
	go build $(GOGCFLAGS) -o "$@" github.com/seveas/herd/cmd/herd

%_grpc.pb.go: %.proto
	protoc --go-grpc_out=. $^

%.pb.go: %.proto
	protoc --go_out=. $^

herd-provider-%: host.go hostset.go go.mod go.sum cmd/herd-provider-%/*.go provider/%/*.go provider/plugin/common/* provider/plugin/server/* $(protobuf_sources)
	go build $(GOGCFLAGS) -o "$@" github.com/seveas/herd/cmd/$@

$(antlr_sources): scripting/Herd.g4
	(cd scripting; antlr -Dlanguage=Go -o parser Herd.g4)

lint:
	golangci-lint run ./...

tidy:
	go mod tidy

provider/plugin/testdata/bin/herd-provider-%: host.go hostset.go go.mod go.sum provider/plugin/testdata/provider/%/*.go provider/plugin/testdata/cmd/herd-provider-%/*.go provider/plugin/common/* provider/plugin/server/* $(protobuf_sources)
	go build $(GOGCFLAGS) -o "$@" github.com/seveas/herd/provider/plugin/testdata/cmd/herd-provider-$*

test: test-providers test-go lint tidy test-build provider/plugin/testdata/bin/herd-provider-ci
test-providers: provider/plugin/testdata/bin/herd-provider-ci provider/plugin/testdata/bin/herd-provider-ci_dataloader provider/plugin/testdata/bin/herd-provider-ci_cache
test-go:
	go test ./...
test-build:
	GOOS=darwin go build github.com/seveas/herd/cmd/herd
	GOOS=linux go build github.com/seveas/herd/cmd/herd
	GOOS=windows go build github.com/seveas/herd/cmd/herd

ABORT ?= --exit-code-from herd --abort-on-container-exit
test-integration:
	go mod vendor
	make -C integration/pki
	test -e integration/openssh/user.key || ssh-keygen -t ecdsa -f integration/openssh/user.key -N ""
	docker-compose down || true
	docker-compose build
	docker-compose up $(ABORT)
	docker-compose down

dist_oses := darwin-amd64 darwin-arm64 dragonfly-amd64 freebsd-amd64 linux-amd64 netbsd-amd64 openbsd-amd64 windows-amd64
VERSION = $(shell go run cmd/version.go)
build-all:
	@echo Building herd
	@$(foreach os,$(dist_oses),echo " - for $(os)" && mkdir -p dist/$(os) && GOOS=$(firstword $(subst -, ,$(os))) GOARCH=$(lastword $(subst -, ,$(os))) go build -tags no_extra -ldflags '-s -w' -o dist/$(os)/herd-$(VERSION)/  github.com/seveas/herd/cmd/herd && tar -C dist/$(os)/ -zcf herd-$(VERSION)-$(os).tar.gz herd-$(VERSION)/;)

clean:
	rm -f herd
	rm -f herd-provider-example
	rm -f provider/plugin/testdata/bin/herd-provider-ci
	rm -f provider/plugin/testdata/bin/herd-provider-ci_dataloader
	rm -f provider/plugin/testdata/bin/herd-provider-ci_cache
	go mod tidy

fullclean: clean
	rm -rf dist/
	rm -f $(antlr_sources)

install:
	go install github.com/seveas/herd/cmd/herd

.PHONY: tidy test build-all clean fullclean install test-go test-build test-integration lint
