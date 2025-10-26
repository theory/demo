FROM debian:trixie-slim
ARG TARGETARCH

COPY lib/Theory/Demo.pm .
ADD --chmod=+x https://github.com/mikefarah/yq/releases/download/v4.47.1/yq_linux_${TARGETARCH} /usr/local/bin/yq

RUN apt-get update \
    # Keep in sync with deb-install-deps in Makefile.
    && DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
        ca-certificates \
        curl \
        libcryptx-perl \
        libhttp-message-perl \
        libipc-system-simple-perl \
        libterm-termkey-perl \
        libwww-curl-perl \
        postgresql-client \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* \
    && mkdir -p "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory \
    && mv Demo.pm "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory/
