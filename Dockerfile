FROM phusion/baseimage:0.9.18
MAINTAINER Sean Clemmer <sczizzo@gmail.com>
ENV DEBIAN_FRONTEND=noninteractive
COPY pkg/*.deb /tmp/
RUN apt-get update \
 && apt-get install -y libsnappy1 libsnappy-dev \
 && dpkg -i /tmp/*.deb \
 && rm -rf /tmp/* \
 && rm -rf /var/lib/apt/lists/*
ENTRYPOINT [ "franz" ]