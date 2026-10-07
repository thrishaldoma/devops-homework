# Part 03 — Networking

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Host:** macOS 26.6.2 (arm64), interface `en0`

This folder has two documents:

| File | Contents |
|---|---|
| `README.md` (this file) | IP addressing and subnetting theory, verified arithmetic, and the macOS-vs-Linux command equivalence table |
| [`networking-commands.md`](./networking-commands.md) | The command lab — every command run inside the Linux container, with its real output and what I understood from it |

---

## Task 1 — IP addressing and subnetting

Source material: `session4-networking/ip.md` from the course repository. I have
reorganised it into tables and **verified every number** rather than restating it,
because the source notes contain at least one error — they label
`197.23.45.10 / 255.255.255.0` as Class A, when the first octet 197 falls in
192–223, which makes it Class C.

### Address classes

| Class | First octet | Default mask | Net / host bits | Usable hosts |
|---|---|---|---|---|
| A | 1–126 | 255.0.0.0 (`/8`) | 8 / 24 | 2²⁴ − 2 = 16,777,214 |
| B | 128–191 | 255.255.0.0 (`/16`) | 16 / 16 | 2¹⁶ − 2 = 65,534 |
| C | 192–223 | 255.255.255.0 (`/24`) | 24 / 8 | 2⁸ − 2 = 254 |
| D | 224–239 | — | — | Multicast |
| E | 240–255 | — | — | Reserved / experimental |

**Why Class A stops at 126, not 127.** The whole of `127.0.0.0/8` is reserved for
loopback. That is why my own machine answers on `127.0.0.1` — visible in the
`ifconfig` output as `lo0: inet 127.0.0.1 netmask 0xff000000`, where `0xff000000`
is `255.0.0.0` written in hex.

**Why "minus two".** In every subnet two addresses cannot be given to a host:

- the **all-zeros** host part is the network address itself (`197.23.45.0`)
- the **all-ones** host part is the broadcast address (`197.23.45.255`)

So a `/24` has 2⁸ = 256 addresses but only 254 assignable ones.

### Private ranges (RFC 1918)

| Private range | CIDR | Where you meet it |
|---|---|---|
| 10.0.0.0 – 10.255.255.255 | `10.0.0.0/8` | Large corporate networks; Docker **overlay** networks |
| 172.16.0.0 – 172.31.255.255 | `172.16.0.0/12` | Docker **bridge** networks |
| 192.168.0.0 – 192.168.255.255 | `192.168.0.0/16` | Home and small-office routers |

That middle row stops being trivia in Phase 7: the user-defined bridge networks
created there are assigned subnets out of `172.16.0.0/12`, which is exactly why
`docker network inspect` reports subnets like `172.19.0.0/16` and `172.20.0.0/16`.

### Worked examples — verified, not asserted

`ipcalc` does not exist on macOS, so I verified the arithmetic with Python's
`ipaddress` module, which implements the same RFC rules. Real captured output:

```
--- 197.23.45.10/24 ---
Netmask        : 255.255.255.0  (/24)
Class          : C  (first octet 197)
Network bits   : 24        Host bits : 8
Network address: 197.23.45.0
Broadcast      : 197.23.45.255
Usable range   : 197.23.45.1 -> 197.23.45.254
Total addresses: 2^8 = 256
Usable hosts   : 2^8 - 2 = 254
Is private     : False

--- 120.27.1.0/8 ---
Netmask        : 255.0.0.0  (/8)
Class          : A  (first octet 120)
Network bits   : 8        Host bits : 24
Network address: 120.0.0.0
Broadcast      : 120.255.255.255
Usable range   : 120.0.0.1 -> 120.255.255.254
Total addresses: 2^24 = 16777216
Usable hosts   : 2^24 - 2 = 16777214
Is private     : False

--- 192.168.10.0/26 ---
Netmask        : 255.255.255.192  (/26)
Class          : C  (first octet 192)
Network bits   : 26        Host bits : 6
Network address: 192.168.10.0
Broadcast      : 192.168.10.63
Usable range   : 192.168.10.1 -> 192.168.10.62
Total addresses: 2^6 = 64
Usable hosts   : 2^6 - 2 = 62
Is private     : True
```

The third example is the interesting one because it is *not* a default class mask.
`/26` borrows two bits from the Class C host part, which splits `192.168.10.0/24`
into four subnets of 62 usable hosts each (`.0–.63`, `.64–.127`, `.128–.191`,
`.192–.255`). That is subnetting proper, rather than just reading a class table —
and `Is private: True` confirms it sits inside `192.168.0.0/16`.

The same three examples are re-verified with `ipcalc` inside the Linux container in
[`networking-commands.md`](./networking-commands.md), so both tools agree.

---

## Bonus — macOS equivalents of the Linux commands

macOS has a BSD userland, so almost none of the `iproute2` commands exist. These
are the equivalents I actually ran on the host; full output is in
[`../logs/03-networking-macos.log`](../logs/03-networking-macos.log).

| Purpose | Linux | macOS |
|---|---|---|
| Show interfaces | `ip addr show` | `ifconfig` |
| Routing table | `ip route show` | `netstat -rn` |
| Listening sockets | `ss -tulnp` | `lsof -nP -iTCP -sTCP:LISTEN` |
| ARP cache | `ip neigh show` | `arp -a` |
| DNS configuration | `cat /etc/resolv.conf` | `scutil --dns` |
| DNS lookup | `dig name` | `dscacheutil -q host -a name` (`dig` also ships with macOS) |
| Interface list | `ip link show` | `networksetup -listallhardwareports` |

### What the host actually reported

**Default route.** `netstat -rn` gave me the single most useful line on the machine:

```
Destination        Gateway            Flags               Netif Expire
default            100.129.160.1      UGScg                 en0
100.129.160/20     link#15            UCS                   en0      !
100.129.160.1      f4:1e:57:3d:a6:d6  UHLWIir               en0   1125
```

My gateway is `100.129.160.1` on `en0`, and the local segment is a `/20`. A `/20`
gives 12 host bits, so 2¹² − 2 = 4094 usable addresses — a much larger subnet than
a home `/24`, which fits a campus or ISP-managed network.

**DNS.** `scutil --dns` shows two resolvers in priority order for `en0`:

```
resolver #1
  nameserver[0] : 100.129.160.1
  nameserver[1] : 8.8.8.8
  if_index : 15 (en0)
```

Resolver #1 is the gateway itself; `8.8.8.8` is the fallback. Having the router as
primary DNS is normal — it usually forwards to the ISP's resolvers.

**ARP cache.** `arp -a` resolved the gateway's name and showed seven other hosts
on the segment:

```
wifi.height8tech.com (100.129.160.1) at f4:1e:57:3d:a6:d6 on en0 ifscope [ethernet]
? (100.129.160.21) at 8a:e6:76:8f:7f:de on en0 ifscope [ethernet]
? (100.129.160.53) at 8e:37:ba:9:fe:fa on en0 ifscope [ethernet]
```

The `?` entries are neighbours whose IPs have no reverse DNS name. Each line is an
IP-to-MAC mapping learned by ARP — these are hosts my machine has actually talked
to, not the whole subnet.

**Reachability, and a real fault.** The ping test did not come back clean:

```
$ ping -c 4 8.8.8.8
64 bytes from 8.8.8.8: icmp_seq=0 ttl=116 time=29.253 ms
64 bytes from 8.8.8.8: icmp_seq=1 ttl=116 time=44.759 ms
Request timeout for icmp_seq 2
64 bytes from 8.8.8.8: icmp_seq=3 ttl=116 time=87.279 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 3 packets received, 25.0% packet loss
round-trip min/avg/max/stddev = 29.253/53.764/87.279/24.530 ms
```

**25% packet loss** and latency swinging from 29 ms to 87 ms. I am keeping this
rather than re-running until it looked tidy, because it explains a second thing I
saw: `host github.com` timed out and `nslookup github.com` returned SERVFAIL, while
`curl -sI https://github.com` returned `HTTP/2 200` in the same minute. On a lossy
link a single UDP DNS query with no retry budget fails, whereas TCP retransmits and
succeeds. Re-probing both resolvers directly confirmed neither was actually broken:

```
$ dig @100.129.160.1 github.com A   ->  status: NOERROR, ANSWER: 1
$ dig @8.8.8.8 github.com A         ->  status: NOERROR, ANSWER: 1
$ dig +short github.com A
20.207.73.82
```

The `ttl=116` in the ping replies is also worth reading. Google's hosts send
ICMP echo replies with an initial TTL of 128, so 128 − 116 = **12 router hops**
between me and `8.8.8.8` — a number I did not have to traceroute to obtain.

**Path to the internet.** `traceroute` confirmed roughly that hop count:

```
traceroute to google.com (142.250.206.110), 12 hops max, 40 byte packets
 1  wifi.height8tech.com (100.129.160.1)  64.283 ms  5.386 ms  5.190 ms
 2  202.131.133.5.convergentindia.com (202.131.133.5)  6.034 ms
 3  115.117.125.189.static-mumbai.vsnl.net.in (115.117.125.189)  9.997 ms
 4  172.28.117.90 (172.28.117.90)  10.478 ms *  24.146 ms
 5  115.112.15.114.static-chennai.vsnl.net.in (115.112.15.114)  20.921 ms
 6  * * *
 7  142.251.55.204 (142.251.55.204)  16.835 ms
10  192.178.254.224 (192.178.254.224)  46.260 ms
```

Two details I would have missed if I had only read a definition of `traceroute`:

- The reverse-DNS names trace the actual physical route — hop 1 is the local Wi-Fi
  router, then an ISP (`convergentindia`), then Tata Communications
  (`vsnl.net.in`) via **Mumbai** and then **Chennai**, before entering Google's
  network at hop 7 (`142.251.x`).
- Hop 4 is `172.28.117.90` — an RFC 1918 **private** address appearing mid-path.
  That is an ISP router numbered from private space internally, which is common and
  is why you cannot assume every hop is publicly routable.
- Hops 6 and 9 printed `* * *`. That is not a broken path — traffic clearly got
  through to hop 10 and beyond. Those routers simply do not generate ICMP
  TTL-exceeded replies, or deprioritise them. Reading `* * *` as an outage is a
  classic misdiagnosis.

**Listening sockets.** `lsof` is the macOS answer to `ss -tulnp`:

```
COMMAND     PID         USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
python3.1 70615 thrishaldoma    3u  IPv4 0xef68c157f7a24c8a      0t0  TCP *:8000 (LISTEN)
Code\x20H  2503 thrishaldoma  512u  IPv4 0x791a8b4dbcbbf192      0t0  TCP 127.0.0.1:49747 (LISTEN)
```

The distinction in the last column is the one that matters for Docker. `*:8000`
means bound to **all** interfaces and reachable from other machines;
`127.0.0.1:49747` is loopback-only. This is the same `0.0.0.0` versus `127.0.0.1`
choice that appears in the Flask app in Phase 5 — binding `127.0.0.1` inside a
container makes it unreachable from the host no matter how the ports are published.

I used exactly this command during preflight to discover that port 3000 was already
taken by a `next-server` process before Phase 5 tried to bind it.
