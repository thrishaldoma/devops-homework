# Ubuntu with systemd running as PID 1, so journalctl works.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session \
      nginx \
      iproute2 iputils-ping dnsutils net-tools traceroute mtr-tiny \
      netcat-openbsd nmap tcpdump whois ipcalc curl wget \
      tree less nano vim procps psmisc file sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Strip units that are meaningless inside a container and slow the boot
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/*

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
