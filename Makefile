VERSION  := v0.1.0
REVISION := $(shell git rev-parse --short HEAD)
REGISTRY ?= localhost:5001

.PHONY: image # Build the OCI image.
image:
	registry=$(REGISTRY) version=$(VERSION) revision=$(REVISION) docker buildx bake $(if $(filter true,$(PUSH)),--push,) --progress plain

.PHONY: test # Run the test suite.
test:
	prove -lv

.PHONY: cover # Run the test suite and produce a coverage report.
cover:
	cover -test -ignore_re '^t\b' -report html

.PHONY: coveralls # Run the test suite and produce a coveralls coverage report.
coveralls:
	cover -test -ignore_re '^t\b' -report html -report coveralls

.PHONY: registry # Run a Docker registry in Docker at localhost:5001.
registry:
	docker run -d -p 5001:5000 --restart always --name registry registry:3

.PHONY: deb-install-deps # Install Apt and Perl dependencies for testing on Debian.
deb-install-deps:
	apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libcryptx-perl \
      libdevel-cover-perl \
      libio-socket-ssl-perl \
      libipc-system-simple-perl \
      libterm-termkey-perl \
      libtest-exception-perl \
      libtest-file-contents-perl \
      libtest-mockmodule-perl \
      libtest-nowarnings-perl \
      liburi-perl \
      libwww-curl-simple-perl \
      libyaml-perl \
      make \
      postgresql-client
	mkdir -p "$$(perl -MConfig -e 'print $$Config{installprivlib}')"/Devel/Cover/Report
	curl -s https://raw.githubusercontent.com/kan/coveralls-perl/refs/heads/master/lib/Devel/Cover/Report/Coveralls.pm -o "$$(perl -MConfig -e 'print $$Config{installprivlib}')"/Devel/Cover/Report/Coveralls.pm
