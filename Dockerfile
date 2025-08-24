FROM perl:5.42-slim

COPY lib/Theory/Demo.pm .

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libterm-termkey-perl \
        libipc-system-simple-perl \
        liburi-perl \
        libwww-curl-simple-perl \
        yq \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/* \
    && mkdir -p "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory \
    && mv Demo.pm "$(perl -MConfig -e 'print $Config{installprivlib}')"/Theory/
