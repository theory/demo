FROM debian:trixie-slim

COPY lib/Theory/Demo.pm .

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libcryptx-perl \
        libio-socket-ssl-perl \
        libipc-system-simple-perl \
        libterm-termkey-perl \
        liburi-perl \
        libwww-curl-simple-perl \
        yq \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* \
    && mkdir -p "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory \
    && mv Demo.pm "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory/
