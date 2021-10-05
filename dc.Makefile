.PHONY: build.docker

BINARY        ?= kibana
VERSION       ?= $(shell git describe --tags --always --dirty)
IMAGE         ?= docker-adobesign-govcloud-forks-release.dr.corp.adobe.com/kibana/$(BINARY)
TAG           ?= ${VERSION}
DOCKERFILE    ?= dc.Dockerfile
GIT_ROOT      ?= $(shell git rev-parse --show-toplevel)

default: build.docker

build.docker:
	docker build --rm -t ${IMAGE}:${TAG} -f $(DOCKERFILE) --build-arg VERSION=$(VERSION) $(GIT_ROOT)
