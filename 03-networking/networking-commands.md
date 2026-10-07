# Part 03 — Networking Command Lab

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Executed in:** Ubuntu 22.04 container (`linux-lab`), built with the full
networking toolset — see [`../01-linux/lab-environment/Dockerfile`](../01-linux/lab-environment/Dockerfile)
**Raw transcript:** [`../logs/03-networking.log`](../logs/03-networking.log) — 32 commands

The theory, subnetting arithmetic and macOS equivalents are in
[`README.md`](./README.md). This file is the command lab: every command, its real
output, what it does, and what I actually learned from the values I saw.

---

## Group 1 — Identity and addressing

### `hostname` / `hostname -I`

```bash
$ hostname
4f1eb9c1623d

$ hostname -I
172.17.0.2
```

**What it does:** prints the system's hostname; `-I` prints all its IP addresses.

**What I understood:** the hostname `4f1eb9c1623d` is the container's short ID —
Docker sets it that way by default, which is why container hostnames look like
hex strings. `hostname -I` gives `172.17.0.2`, an address from
**172.17.0.0/16**. That lands inside the `172.16.0.0/12` RFC 1918 block I
documented in the theory section, and confirms in practice that Docker's default
bridge draws from private space.

### `ip addr show` and `ip -brief addr`

```bash
$ ip -brief addr
lo               UNKNOWN        127.0.0.1/8 ::1/128
tunl0@NONE       DOWN
gre0@NONE        DOWN
gretap0@NONE     DOWN
erspan0@NONE     DOWN
ip_vti0@NONE     DOWN
ip6_vti0@NONE    DOWN
sit0@NONE        DOWN
ip6tnl0@NONE     DOWN
ip6gre0@NONE     DOWN
eth0@if21        UP             172.17.0.2/16
```

```bash
$ ip addr show          # (extract)
11: eth0@if21: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP group default
    link/ether 6e:5c:94:06:90:29 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```

**What it does:** the modern replacement for `ifconfig` — lists interfaces with
their IPv4/IPv6 addresses, CIDR prefix, MAC address and MTU.

**What I understood:** three specifics stood out. First, `eth0@if21` — the `@if21`
suffix means this is one end of a **veth pair**, and its partner is interface
index 21 in another namespace (the Docker bridge on the VM side). That is
literally how container networking is wired. Second, the MTU is **65535**, not the
usual 1500; Docker Desktop's VMM uses a virtualised link where there is no
physical Ethernet frame limit to respect, so it can afford enormous frames for
loopback-like performance. Third, the interfaces `tunl0`, `gre0`, `sit0` and the
rest are all `DOWN` — they are tunnel drivers the kernel exposes but nothing has
configured, and it would be a mistake to read them as active VPNs.

### `ip link show`

```bash
$ ip link show          # (extract)
11: eth0@if21: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP mode DEFAULT
    link/ether 6e:5c:94:06:90:29 brd ff:ff:ff:ff:ff:ff link-netnsid 0
```

**What it does:** shows layer-2 information only — interfaces, MAC addresses,
state and MTU, with no IP addresses.

**What I understood:** this is the same interface list as `ip addr` minus the
`inet` lines, which makes the layering explicit: `ip link` is Ethernet, `ip addr`
adds IP on top. The MAC `6e:5c:94:06:90:29` starts with `6e`, and the second hex
digit `e` has the locally-administered bit set — Docker generated this address
rather than it belonging to any hardware vendor.

### `ifconfig`

```bash
$ ifconfig
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 65535
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 6e:5c:94:06:90:29  txqueuelen 0  (Ethernet)
        RX packets 20  bytes 1670 (1.6 KB)
        TX packets 11  bytes 622 (622.0 B)

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        RX packets 10  bytes 1468 (1.4 KB)
```

**What it does:** the legacy (`net-tools`) interface listing.

**What I understood:** it shows the same address as `ip addr` but expresses the
prefix as a dotted netmask `255.255.0.0` instead of `/16` — the same information
in the older notation. It also adds packet counters that `ip addr` omits: only
**20 packets received** on `eth0`, because the container had barely done any
networking at that point. Notably `ifconfig` does *not* list the ten DOWN tunnel
interfaces, which is one reason `ip` is preferred — the legacy tool hides state.

---

## Group 2 — Routing

### `ip route show` and `route -n`

```bash
$ ip route show
default via 172.17.0.1 dev eth0
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2

$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG    0      0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 eth0
```

**What it does:** prints the kernel routing table — where packets go for each
destination prefix.

**What I understood:** there are exactly two routes, and between them they cover
everything. The second is a **directly connected** route: anything in
`172.17.0.0/16` is on my own link, reachable without a router (note `scope link`,
and Gateway `0.0.0.0` in `route -n`, meaning "no gateway needed"). The first is
the **default route** — everything else goes to `172.17.0.1`, which is Docker's
bridge gateway. This is the first thing I would check if the container could not
reach the internet: no `default via` line means no route off-link, regardless of
whether DNS works. The two tools agree exactly; `route -n` just writes the default
route as `0.0.0.0` with flag `G` for "gateway".

### `ip neigh show`

```bash
$ ip neigh show
172.17.0.1 dev eth0 lladdr ca:c1:ea:59:c9:69 STALE
```

**What it does:** prints the ARP/neighbour cache — learned IP-to-MAC mappings for
the local segment.

**What I understood:** there is exactly **one** entry, for the gateway
`172.17.0.1`. That makes sense and is informative: the container has only ever
talked to its gateway, because every destination it contacted was off-link and
therefore routed through it. Contrast this with the Mac host, whose `arp -a`
listed eight neighbours on a shared office network. The state `STALE` means the
mapping is still usable but its validity timer has expired, so the kernel will
re-verify with an ARP probe before relying on it — it is not an error.

---

## Group 3 — Reachability

### `ping IP` versus `ping name` — the key diagnostic pair

```bash
$ ping -c 4 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=1 ttl=63 time=18.3 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=63 time=13.9 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=63 time=12.1 ms
64 bytes from 8.8.8.8: icmp_seq=4 ttl=63 time=48.6 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3016ms
rtt min/avg/max/mdev = 12.122/23.233/48.598/14.814 ms

$ ping -c 4 google.com
PING google.com (142.251.221.238) 56(84) bytes of data.
64 bytes from 142.251.221.238: icmp_seq=1 ttl=63 time=35.8 ms
...
4 packets transmitted, 4 received, 0% packet loss, time 13237ms
rtt min/avg/max/mdev = 26.213/57.652/103.810/30.193 ms
```

**What it does:** sends ICMP echo requests. Running both forms separates a routing
fault from a DNS fault — the single most useful diagnostic pair in networking.

**What I understood:** both succeeded, so routing *and* DNS are working; had the
IP form worked and the name form failed, the problem would be purely DNS. The
`ttl=63` is the detail worth reading: replies arrive with TTL decremented once per
hop, and 63 (one below the round 64 that Linux hosts use as their initial value)
means **one hop** consumed — but I know from `traceroute` that the real path is
many hops. The container is behind Docker's NAT, which rewrites and re-originates
the packets, so the TTL I see reflects only the last leg. That is a concrete
demonstration that NAT is not transparent. Comparing with the macOS host, where
`ttl=116` implied 12 hops, makes the difference obvious.

It is also worth noting the container saw **0% packet loss** while the macOS host
saw 25% on the same target minutes earlier, and that `ping google.com` took
13.2 seconds of wall clock for four packets that should take 3 — the latency
range 26–104 ms shows the same link instability, just not severe enough to drop
packets that time.

### `traceroute`

```bash
$ traceroute -m 12 -w 2 google.com
traceroute to google.com (142.251.221.238), 12 hops max, 60 byte packets
 1  172.17.0.1 (172.17.0.1)  0.250 ms  0.183 ms  0.168 ms
 2  * * *
 3  * * *
 ...
12  * * *
```

**What it does:** reveals each router on the path by sending packets with
increasing TTL and reading the ICMP "time exceeded" replies.

**What I understood:** only hop 1 answered — `172.17.0.1`, the Docker gateway, at
**0.25 ms** (it is in the same VM, so effectively instant). Every subsequent hop
timed out, even though `ping google.com` to the same destination succeeded with 0%
loss in the same session. So this is emphatically *not* a broken path. Docker
Desktop's NAT layer does not forward the ICMP TTL-exceeded messages back into the
container, so traceroute has nothing to display. The same traceroute run from the
macOS host produced a full path through Mumbai and Chennai. The lesson is that
traceroute output is only as truthful as the network's willingness to send ICMP
errors, and inside a NAT-ed container it is close to useless — which is why I ran
it on the host as well rather than concluding the container had no internet.

### `nc -zv host port`

```bash
$ nc -zv github.com 443
Connection to github.com (20.207.73.82) 443 port [tcp/*] succeeded!
```

**What it does:** attempts a TCP connection and reports success without sending
data (`-z` = scan, `-v` = verbose). The fastest proof that a port is open.

**What I understood:** this proves reachability at layer 4, which `ping` cannot —
many hosts drop ICMP but accept TCP. It also resolved the name for me, showing
`20.207.73.82`. I use this same command in Phase 7 to prove container-to-container
connectivity to MySQL on port 3306, where it is the right tool precisely because
it needs no client library.

---

## Group 4 — DNS

### `cat /etc/resolv.conf`

```bash
$ cat /etc/resolv.conf
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 192.168.65.7

# Based on host file: '/etc/resolv.conf' (legacy)
# Overrides: []
```

**What it does:** the resolver configuration — which nameservers the system asks.

**What I understood:** Docker **generated** this file, and it points at a single
nameserver, `192.168.65.7`. That is not one of the resolvers the Mac uses
(`100.129.160.1` and `8.8.8.8`); it is an address inside Docker Desktop's own VM
network. So container DNS queries go to Docker's resolver, which forwards them to
whatever the host is configured to use. This matters for Phase 7: the embedded
resolver is also what provides container-name DNS on user-defined networks.

### `dig`

```bash
$ dig google.com
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 38544
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;google.com.			IN	A

;; ANSWER SECTION:
google.com.		355	IN	A	142.251.221.238

;; Query time: 2 msec
;; SERVER: 192.168.65.7#53(192.168.65.7) (UDP)
```

**What it does:** the proper DNS diagnostic tool — shows the question, the answer
section, record type, TTL, which server answered and how long it took.

**What I understood:** `status: NOERROR` with `ANSWER: 1` is a clean successful
lookup. The **355** before `IN A` is the remaining TTL in seconds — this answer
came from a cache and will be discarded in under six minutes, which is why Google's
addresses appear to change between lookups. `SERVER: 192.168.65.7#53` confirms
Docker's resolver answered, and `Query time: 2 msec` confirms it was cached
locally. The flags `rd ra` mean I requested recursion and the server is willing to
recurse.

### `dig +short` and `dig -x` (reverse lookup)

```bash
$ dig +short google.com A
142.251.221.238

$ dig -x 8.8.8.8
;; ANSWER SECTION:
8.8.8.8.in-addr.arpa.	4502	IN	PTR	dns.google.

;; Query time: 3094 msec
```

**What it does:** `+short` prints just the answer, for use in scripts. `-x` does a
reverse lookup, IP to name.

**What I understood:** `-x` works by querying a **PTR** record under the special
`in-addr.arpa` domain, with the octets reversed — visible in the question as
`8.8.8.8.in-addr.arpa`. The answer `dns.google.` has a trailing dot, marking it as
a fully-qualified name rooted at the DNS root. The contrast in timing is the
interesting part: this query took **3094 ms** against the previous query's 2 ms,
because the PTR record was not cached and had to be resolved recursively across
the internet. Cache state, not server speed, dominates DNS latency.

### `nslookup` and `host`

```bash
$ nslookup github.com
;; communications error to 192.168.65.7#53: timed out
Server:		192.168.65.7
Address:	192.168.65.7#53

Non-authoritative answer:
Name:	github.com
Address: 20.207.73.82

$ host github.com
github.com has address 20.207.73.82
github.com mail is handled by 0 github-com.mail.protection.outlook.com.
```

**What it does:** two older lookup tools. `nslookup` is interactive-capable;
`host` gives a one-line human-readable summary.

**What I understood:** `nslookup` shows a genuine transient fault and its
recovery in one output — `communications error ... timed out` followed by a
successful answer on retry. That is the same link instability seen in the ping
results, and it is why DNS clients retry. "Non-authoritative" means the answer
came from a cache rather than from GitHub's own nameservers. `host` volunteered
the **MX** record unasked, and it is revealing: GitHub's mail is handled by
`github-com.mail.protection.outlook.com`, i.e. Microsoft 365 — a small piece of
infrastructure intelligence from a one-word command.

The address `20.207.73.82` is also worth noting: it is in Microsoft Azure space
and geographically local to this connection, so GitHub's CDN returned a
region-specific answer rather than a single global IP.

---

## Group 5 — Sockets and services

### `ss -tulnp`

```bash
$ ss -tulnp
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=730,fd=6),...,("nginx",pid=715,fd=6))
tcp   LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=730,fd=7),...,("nginx",pid=715,fd=7))
```

**What it does:** lists listening sockets with the owning process.
`-t` TCP, `-u` UDP, `-l` listening, `-n` numeric, `-p` process.

**What I understood:** this answers "what is already on port 80?" — the question
that matters *before* a Docker bind fails with "address already in use". Two
details repay attention. The listen address is `0.0.0.0:80`, meaning **all**
interfaces; had nginx bound `127.0.0.1:80` it would be unreachable from outside
the container no matter how ports were published — exactly the mistake the Flask
app in Phase 5 avoids with `host="0.0.0.0"`. And **sixteen** nginx PIDs share the
same socket: the master plus fifteen workers all inherited the listening file
descriptor, which is how nginx load-balances accepts across workers without a
lock. `Send-Q 511` is the accept backlog.

### `netstat -tulnp`

```bash
$ netstat -tulnp
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      715/nginx: master p
tcp6       0      0 :::80                   :::*                    LISTEN      715/nginx: master p
```

**What it does:** the legacy equivalent of `ss`.

**What I understood:** same two sockets, but it credits only **one** PID — the
master, 715 — where `ss` showed all sixteen sharing the descriptor. `ss` reads
from the kernel's `sock_diag` netlink interface while `netstat` parses
`/proc/net/tcp`, and the newer interface simply carries more information. It also
writes IPv6 as `:::80` rather than `[::]:80`. Same facts, less detail.

### `ss -s` (summary)

```bash
$ ss -s
Total: 66
TCP:   23 (estab 0, closed 21, orphaned 0, timewait 0)

Transport Total     IP        IPv6
TCP	  2         1         1
INET	  2         1         1
```

**What it does:** a socket census rather than a listing.

**What I understood:** `Total: 66` counts all sockets including Unix domain
sockets, which dominate on a systemd host (journald, dbus and logind all
communicate that way). Of 23 TCP sockets, **21 are `closed`** and 0 established —
those are remnants of the earlier `curl`, `dig` and `nc` commands still being
tracked. Only 2 are live, and they are the two nginx listeners, one IPv4 and one
IPv6. A high `timewait` count here would be the classic signature of a service
churning through short-lived connections.

### `nmap -F localhost`

```bash
$ nmap -F localhost
Nmap scan report for localhost (127.0.0.1)
Host is up (0.0000010s latency).
Other addresses for localhost (not scanned): ::1
Not shown: 99 closed ports
PORT   STATE SERVICE
80/tcp open  http

Nmap done: 1 IP address (1 host up) scanned in 0.04 seconds
```

**What it does:** port scanner; `-F` scans only the 100 most common ports.

**What I understood:** of 100 ports probed, **99 closed and 1 open** — and the one
open port, 80, matches exactly what `ss -tulnp` reported. That cross-check is the
point: `ss` asks the local kernel what it is listening on, whereas `nmap` probes
from the outside and reports what is actually reachable. When those two disagree,
the answer is usually a firewall. "Closed" here is distinct from "filtered": the
host actively refused with a TCP RST rather than silently dropping, which is what
you would expect with no firewall in the way.

---

## Group 6 — HTTP, external identity, and packet capture

### `curl -sI` — and a real failure worth keeping

The first attempt appeared to return nothing at all. Re-running with `-S` to stop
suppressing errors revealed why:

```bash
$ curl -sSI https://github.com
curl: (77) error setting certificate file: /etc/ssl/certs/ca-certificates.crt
```

Diagnosis and fix:

```bash
$ dpkg -l ca-certificates | tail -1
un  ca-certificates <none>  <none>  (no description available)

$ apt-get install -y ca-certificates && update-ca-certificates
$ curl -sSI https://github.com | head -4
HTTP/2 200
date: Fri, 04 Sep 2026 17:22:52 GMT
content-type: text/html; charset=utf-8
content-language: en-US
```

**What it does:** `-I` fetches headers only — status code, server software,
redirects — without downloading the body.

**What I understood:** the lab image was built with `--no-install-recommends`,
which kept it to 217 packages but omitted `ca-certificates`. Without a CA trust
bundle `curl` cannot verify any TLS certificate, so **every** HTTPS request fails
with error 77. The `-s` flag hid the error entirely, which is the real lesson:
`-s` silences errors as well as progress, so `-sS` is the correct combination for
scripts. Once fixed, `HTTP/2 200` confirms GitHub negotiated HTTP/2 over TLS.
This is recorded as Issue 7 in [`../logs/ISSUES.md`](../logs/ISSUES.md).

### `curl -s ifconfig.me`

```bash
$ curl -s ifconfig.me
202.131.133.51
```

**What it does:** asks an external service to report the public IP it sees.

**What I understood:** this is the single most interesting result in the lab. The
container believes its address is `172.17.0.2`; the internet sees
**`202.131.133.51`**. Two layers of NAT sit between them — Docker's bridge, then
the ISP's router. And this address is not arbitrary: the `traceroute` run from the
macOS host showed hop 2 as `202.131.133.5.convergentindia.com`. My public address
and that router are in the **same `202.131.133.0/24`**, which identifies the ISP
performing the outermost translation. Two unrelated commands corroborating each
other is exactly the kind of cross-check that makes a diagnosis trustworthy.

### `whois` — a second real failure, same root cause

```bash
$ whois github.com | head -25
getaddrinfo(whois.verisign-grs.com): Servname not supported for ai_socktype
```

The port itself was reachable, which isolated the fault to name resolution rather
than connectivity:

```bash
$ nc -zv -w 5 whois.verisign-grs.com 43
Connection to whois.verisign-grs.com (192.30.45.30) 43 port [tcp/*] succeeded!

$ ls /etc/services
ls: cannot access '/etc/services': No such file or directory

$ whois -h whois.verisign-grs.com -p 43 github.com | head -10
   Domain Name: GITHUB.COM
   Registry Domain ID: 1264983250_DOMAIN_COM-VRSN
   Registrar WHOIS Server: whois.markmonitor.com
   Registrar URL: http://www.markmonitor.com
   Updated Date: 2024-09-07T09:16:32Z
   Creation Date: 2007-10-09T18:20:50Z
   Registry Expiry Date: 2026-10-09T18:20:50Z
   Registrar: MarkMonitor Inc.
   Registrar IANA ID: 292
   Registrar Abuse Contact Email: abusecomplaints@markmonitor.com
```

**What it does:** queries registry databases for domain registration details over
TCP port 43.

**What I understood:** the error message is precise once you can read it —
"Servname not supported" is about the *service name*, not the host. `whois` asked
`getaddrinfo()` to translate the service `whois` into a port number, and that
lookup needs `/etc/services`, which the `netbase` package provides and
`--no-install-recommends` had omitted. Passing `-p 43` supplies the port directly
and bypasses the lookup entirely — the smaller fix than installing a package.
Same root cause as the `curl` failure above, presenting completely differently.

The data itself is a reminder that WHOIS is a two-tier system: Verisign runs the
`.com` registry and refers me on to `whois.markmonitor.com`, GitHub's registrar,
for the detailed record. `Creation Date: 2007-10-09` is GitHub's actual
registration date.

### `tcpdump` — ground truth

```bash
$ tcpdump -i any -c 10 -nn port 80 & sleep 1; curl -s localhost >/dev/null; wait
tcpdump: data link type LINUX_SLL2
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
10 packets captured
20 packets received by filter
0 packets dropped by kernel

17:19:57.455426 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [S],  seq 511799250, ...
17:19:57.455448 lo In IP 127.0.0.1.80 > 127.0.0.1.55520: Flags [S.], seq 1207467818, ack 511799251, ...
17:19:57.455468 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [.],  ack 1, ...
17:19:57.455535 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [P.], seq 1:74,  ack 1, length 73: HTTP: GET / HTTP/1.1
17:19:57.455540 lo In IP 127.0.0.1.80 > 127.0.0.1.55520: Flags [.],  ack 74, ...
17:19:57.456138 lo In IP 127.0.0.1.80 > 127.0.0.1.55520: Flags [P.], seq 1:860, ack 74, length 859: HTTP: HTTP/1.1 200 OK
17:19:57.456155 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [.],  ack 860, ...
17:19:57.456241 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [F.], seq 74,  ack 860, ...
17:19:57.456277 lo In IP 127.0.0.1.80 > 127.0.0.1.55520: Flags [F.], seq 860, ack 75, ...
17:19:57.456299 lo In IP 127.0.0.1.55520 > 127.0.0.1.80: Flags [.],  ack 861, ...
```

**What it does:** captures packets off the wire. `-i any` all interfaces,
`-c 10` stop after ten, `-nn` no name or port resolution, `port 80` the filter.

**What I understood:** those ten packets are a complete HTTP request/response
lifecycle, and reading the `Flags` column tells the whole story:

1. **`[S]`** — the client's SYN opens the connection
2. **`[S.]`** — the server's SYN-ACK (the `.` is ACK), completing two of three steps
3. **`[.]`** — the client's ACK finishes the **three-way handshake**
4. **`[P.]` with `length 73`** — PSH carrying the actual `GET / HTTP/1.1`
5. **`[P.]` with `length 859`** — the `HTTP/1.1 200 OK` response
6. **`[F.]` both directions** — FIN from each side, the four-way close

The whole exchange took **0.87 milliseconds** (455426 → 456299 microseconds)
because it never left the loopback interface. Two other details: the sequence
numbers start at random values (511799250 and 1207467818) rather than zero, which
is a deliberate defence against sequence prediction attacks; and the counters
report `20 packets received by filter` against `10 packets captured` because
`-i any` sees each loopback packet twice, once outbound and once inbound. Zero
packets were dropped by the kernel, so the capture is complete.

This is why `tcpdump` is the tool of last resort but the first source of truth: it
does not report what a program *thinks* happened, it reports the bytes.

---

## Group 7 — Subnetting verified with `ipcalc`

The same three examples computed in [`README.md`](./README.md) with Python, now
re-verified with the standard tool. Both agree exactly.

```bash
$ ipcalc 197.23.45.10/24
Address:   197.23.45.10         11000101.00010111.00101101. 00001010
Netmask:   255.255.255.0 = 24   11111111.11111111.11111111. 00000000
Wildcard:  0.0.0.255            00000000.00000000.00000000. 11111111
=>
Network:   197.23.45.0/24       11000101.00010111.00101101. 00000000
HostMin:   197.23.45.1          11000101.00010111.00101101. 00000001
HostMax:   197.23.45.254        11000101.00010111.00101101. 11111110
Broadcast: 197.23.45.255        11000101.00010111.00101101. 11111111
Hosts/Net: 254                   Class C

$ ipcalc 120.27.1.0/8
Netmask:   255.0.0.0 = 8        11111111. 00000000.00000000.00000000
Network:   120.0.0.0/8          01111000. 00000000.00000000.00000000
HostMin:   120.0.0.1
HostMax:   120.255.255.254
Broadcast: 120.255.255.255
Hosts/Net: 16777214              Class A

$ ipcalc 192.168.10.0/26
Address:   192.168.10.0         11000000.10101000.00001010.00 000000
Netmask:   255.255.255.192 = 26 11111111.11111111.11111111.11 000000
Wildcard:  0.0.0.63             00000000.00000000.00000000.00 111111
=>
Network:   192.168.10.0/26      11000000.10101000.00001010.00 000000
HostMin:   192.168.10.1
HostMax:   192.168.10.62
Broadcast: 192.168.10.63
Hosts/Net: 62                    Class C, Private Internet
```

**What I understood:** the binary column is what makes subnetting finally obvious.
`ipcalc` prints a **space at the prefix boundary**, so you can see the split
directly. In the `/24` and `/8` cases the space falls on an octet boundary, which
is why classful masks are easy to do in your head. In the `/26` case the space
falls *inside* the last octet — `00001010.00` — showing the two borrowed bits, and
that is exactly why `/26` arithmetic feels harder: the boundary no longer lines up
with the dots.

Three cross-checks confirm my earlier working: `254`, `16777214` and `62` usable
hosts, identical to the Python `ipaddress` results. `ipcalc` independently
classifies `197.23.45.10` as **Class C**, confirming the reference material's
`ip.md` was wrong to label it Class A. And it flags `192.168.10.0/26` as
"Private Internet" while the other two are not — matching Python's
`is_private: True/False/False`.

---

## Summary of commands documented

| # | Command | Group |
|---|---|---|
| 1 | `hostname` | Identity |
| 2 | `hostname -I` | Identity |
| 3 | `ip addr show` | Addressing |
| 4 | `ip -brief addr` | Addressing |
| 5 | `ip link show` | Addressing |
| 6 | `ifconfig` | Addressing (legacy) |
| 7 | `ip route show` | Routing |
| 8 | `route -n` | Routing (legacy) |
| 9 | `ip neigh show` | Routing / ARP |
| 10 | `ping -c 4 8.8.8.8` | Reachability |
| 11 | `ping -c 4 google.com` | Reachability |
| 12 | `traceroute -m 12 google.com` | Reachability |
| 13 | `nc -zv github.com 443` | Reachability (TCP) |
| 14 | `cat /etc/resolv.conf` | DNS |
| 15 | `cat /etc/hosts` | DNS |
| 16 | `dig google.com` | DNS |
| 17 | `dig +short google.com A` | DNS |
| 18 | `dig -x 8.8.8.8` | DNS (reverse) |
| 19 | `nslookup github.com` | DNS |
| 20 | `host github.com` | DNS |
| 21 | `ss -tulnp` | Sockets |
| 22 | `netstat -tulnp` | Sockets (legacy) |
| 23 | `ss -s` | Sockets |
| 24 | `nmap -F localhost` | Sockets (external view) |
| 25 | `curl -sSI https://github.com` | HTTP |
| 26 | `curl -s ifconfig.me` | HTTP / NAT |
| 27 | `whois github.com` | Registry |
| 28 | `tcpdump -i any -c 10 -nn port 80` | Packet capture |
| 29 | `ipcalc 197.23.45.10/24` | Subnetting |
| 30 | `ipcalc 120.27.1.0/8` | Subnetting |
| 31 | `ipcalc 192.168.10.0/26` | Subnetting |
| 32 | `nc -zv whois.verisign-grs.com 43` | Diagnostic follow-up |

**32 commands**, against the required minimum of 15. Two produced genuine
failures that I diagnosed to root cause rather than dropping — both traced to
`--no-install-recommends` omitting `ca-certificates` and `netbase`.
