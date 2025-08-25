VERSION  := v0.1.0
REVISION := $(shell git rev-parse --short HEAD)
REGISTRY ?= localhost:5001

.PHONY: image # Build the OCI image.
image:
	registry=$(REGISTRY) version=$(VERSION) revision=$(REVISION) docker buildx bake $(if $(filter true,$(PUSH)),--push,) --progress plain

.PHONY: test # Run the test suite.
test:
	prove -l

.PHONY: registry # Run a Docker registry in Docker at localhost:5001.
registry:
	docker run -d -p 5001:5000 --restart always --name registry registry:3
