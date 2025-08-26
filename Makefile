VERSION  := v0.1.0
REVISION := $(shell git rev-parse --short HEAD)
REGISTRY ?= localhost:5001

.PHONY: image # Build the OCI image.
image:
	registry=$(REGISTRY) version=$(VERSION) revision=$(REVISION) docker buildx bake $(if $(filter true,$(PUSH)),--push,) --progress plain

.PHONY: test # Run the test suite.
test:
	prove -lv

.PHONY: registry # Run a Docker registry in Docker at localhost:5001.
registry:
	docker run -d -p 5001:5000 --restart always --name registry registry:3

.PHONY: apt-install-deps # Install Apt dependencies.
apt-install-deps:
	apt-get install -y --no-install-recommends \
      ca-certificates \
      libcryptx-perl \
      libio-socket-ssl-perl \
      libipc-system-simple-perl \
      libterm-termkey-perl \
      liburi-perl \
      libwww-curl-simple-perl \
      postgresql-client
