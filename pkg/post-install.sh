#!/usr/bin/env bash
useradd --user-group --system -M --shell /bin/false franz || true
mkdir -p /etc/franz /var/data/franz
chown -R franz:franz /opt/franz /etc/franz /var/data/franz