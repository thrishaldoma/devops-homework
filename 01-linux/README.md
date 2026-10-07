# Part 01 — Linux Fundamentals

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Environment:** macOS host + Ubuntu 22.04 container with systemd as PID 1
(see [`lab-environment/Dockerfile`](./lab-environment/Dockerfile))

---

## Why a container

macOS has no `adduser`, no `useradd` and no `journalctl`, and its BSD userland
takes different flags from GNU coreutils. `journalctl` cannot exist on macOS at
all, because there is no systemd — macOS uses `launchd` and the unified logging
system (`log show`). Faking these tasks on the host would have produced output
that does not match the homework and would have taught me the wrong commands.

So all four tasks were executed inside an Ubuntu 22.04 container built from
`lab-environment/Dockerfile`, running **systemd as PID 1** so that `systemctl`
and `journalctl` behave exactly as they do on a real Linux server. This was a
deliberate engineering decision, not a workaround to hide.

Confirming the lab really did boot systemd, rather than assuming it:

```bash
$ docker exec linux-lab ps -p 1 -o comm=
systemd

$ docker exec linux-lab systemctl is-system-running
running

$ docker exec linux-lab systemctl status systemd-journald --no-pager | head -6
● systemd-journald.service - Journal Service
     Loaded: loaded (/lib/systemd/system/systemd-journald.service; static)
     Active: active (running) since Fri 2026-09-04 17:10:41 UTC; 10s ago
TriggeredBy: ● systemd-journald.socket
             ● systemd-journald-dev-log.socket
             ● systemd-journald-audit.socket
```

PID 1 is `systemd` and `is-system-running` returns `running` — not even the
`degraded` that is normally acceptable in a container. The documented journald
fallback was therefore not needed.

Getting there requires four flags that are easy to miss, which is why the image
alone is not enough:

```bash
docker run -d --name linux-lab \
  --privileged \
  --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock \
  linux-lab:v1
```

`--cgroupns=host` plus the cgroup mount let systemd manage units; the two
`--tmpfs` mounts give it writable runtime directories. Without them PID 1 exits
immediately and every `systemctl` call fails with "Failed to connect to bus".

---

## Task 1 — Soft link vs hard link

### Comparison

| Property | Hard link | Soft link (symlink) |
|---|---|---|
| Command | `ln target link` | `ln -s target link` |
| Inode | **Same** as target | Its own |
| Original deleted | Data survives | Link dangles |
| Cross-filesystem | Not allowed | Allowed |
| Directories | Not allowed | Allowed |
| Link count | Increments | Target unchanged |
| Typical use | `rsync --link-dest` backups | `/usr/bin` version switching, config symlinks |

### Creating both

```bash
$ echo "This is the original file content." > original.txt && ls -li original.txt
66068 -rw-r--r-- 1 root root 35 Sep  4 17:11 original.txt

$ ln original.txt hardlink.txt && ln -s original.txt softlink.txt && ls -li
total 8
66068 -rw-r--r-- 2 root root 35 Sep  4 17:11 hardlink.txt
66068 -rw-r--r-- 2 root root 35 Sep  4 17:11 original.txt
66069 lrwxrwxrwx 1 root root 12 Sep  4 17:11 softlink.txt -> original.txt
```

Three things in that one listing are the whole lesson:

- `original.txt` and `hardlink.txt` both show inode **66068** — the same inode
  number. They are not copies; they are two directory entries naming one object.
- Their link count has become **2** (third column). `original.txt` alone was 1.
- `softlink.txt` has its **own** inode 66069, type `l`, and size **12** — which is
  exactly the number of characters in the string `original.txt`. A symlink is a
  tiny file whose contents are the target's path.

All three names read the same data:

```bash
$ cat original.txt; cat hardlink.txt; cat softlink.txt
This is the original file content.
This is the original file content.
This is the original file content.
```

Writing through the hard link changes what the original name shows, because there
is only one file:

```bash
$ echo "Line added via the hard link." >> hardlink.txt && cat original.txt
This is the original file content.
Line added via the hard link.

$ stat original.txt
  File: original.txt
  Size: 65        	Blocks: 8          IO Block: 4096   regular file
Device: 2fh/47d	Inode: 66068       Links: 2
```

`Links: 2` is the inode's reference count. `readlink` shows what the symlink
stores versus where it actually leads:

```bash
$ readlink softlink.txt
original.txt
$ readlink -f softlink.txt
/root/links-lab/original.txt
```

### Proof: deleting the original

```bash
$ rm original.txt && ls -li
total 4
66068 -rw-r--r-- 1 root root 65 Sep  4 17:11 hardlink.txt
66069 lrwxrwxrwx 1 root root 12 Sep  4 17:11 softlink.txt -> original.txt

$ cat hardlink.txt
This is the original file content.
Line added via the hard link.

$ cat softlink.txt
cat: softlink.txt: No such file or directory
[exit: 1]
```

This is the decisive test. `rm original.txt` removed **one directory entry**, and
the link count on inode 66068 dropped from 2 to 1 — visible in the listing. The
data is still there and `hardlink.txt` reads it perfectly, including the line I
appended. The symlink, however, still stores the literal string `original.txt`,
and that name no longer resolves, so `cat` fails with exit code 1.

And because a symlink is resolved at open time, it *heals* the moment a file of
that name exists again:

```bash
$ cp hardlink.txt original.txt && cat softlink.txt
This is the original file content.
Line added via the hard link.
```

Nothing was done to the symlink itself. That is the difference between storing a
reference to an object and storing a string to be looked up later.

### The two restrictions on hard links

```bash
$ ln -s mydir dirlink && ls -ld dirlink
lrwxrwxrwx 1 root root 5 Sep  4 17:11 dirlink -> mydir

$ ln mydir dirhard
ln: mydir: hard link not allowed for directory
[exit: 1]
```

A symlink to a directory is fine — note its size is **5**, the length of `mydir`.
A hard link to a directory is refused outright. Finding links, including broken
ones:

```bash
$ find . -type l -ls
    66069      0 lrwxrwxrwx   1 root root  12 Sep  4 17:11 ./softlink.txt -> original.txt
    66072      0 lrwxrwxrwx   1 root root   5 Sep  4 17:11 ./dirlink -> mydir

$ ln -s /nonexistent broken && find . -xtype l
./broken
```

`find -type l` lists all symlinks; `-xtype l` lists only the **broken** ones,
which is the practical way to audit a filesystem for dangling links.

### Interview answer

A hard link is a second directory entry pointing at the same inode, so the two
names are equal peers — there is no "original" and "copy", and nothing in the
filesystem records which name came first. The inode carries a reference count,
and the data is only freed when that count reaches zero, which is why deleting
one name leaves the other perfectly usable. Because inode numbers are only unique
within a single filesystem, a hard link can never cross a filesystem boundary,
and hard links to directories are forbidden because they would let you build
cycles in the directory tree that tools like `find` could never terminate on.

A soft link is a different thing entirely: a small file whose *contents* are a
path string, resolved every time it is opened. That indirection is what buys the
flexibility — it can cross filesystems, point at a directory, and even point at
something that does not exist yet, which is how package managers stage upgrades.
The price is that it dangles the moment the target moves or is deleted, and that
every access costs an extra path resolution.

In practice I would reach for a hard link when I want two names for one piece of
data with no dependency on either name surviving — deduplicated backups being the
classic case — and a symlink whenever I want a stable name that *points at*
something I intend to change later, like `/usr/bin/python3` following a version.

---

## Task 2 — `adduser` vs `useradd`

### They are not the same kind of program

The first thing worth establishing is that these are not two flags on one tool:

```bash
$ which adduser useradd
/usr/sbin/adduser
/usr/sbin/useradd

$ file /usr/sbin/adduser /usr/sbin/useradd
/usr/sbin/adduser: Perl script text executable
/usr/sbin/useradd: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV),
                   dynamically linked, ..., stripped

$ head -3 /usr/sbin/adduser
#!/usr/bin/perl

# adduser: a utility to add users to the system
```

`useradd` is a compiled binary from the `shadow` package — the low-level tool.
`adduser` is a **Perl script that calls it**, adding Debian/Ubuntu policy on top.
That policy is a readable config file:

```bash
$ grep -vE '^\s*#|^$' /etc/adduser.conf | head -12
DSHELL=/bin/bash
DHOME=/home
GROUPHOMES=no
LETTERHOMES=no
SKEL=/etc/skel
FIRST_SYSTEM_UID=100
LAST_SYSTEM_UID=999
FIRST_SYSTEM_GID=100
LAST_SYSTEM_GID=999
FIRST_UID=1000
LAST_UID=59999
FIRST_GID=1000
```

### Creating a user the recommended way

`adduser` is normally interactive, so I drove it non-interactively for
reproducibility:

```bash
$ adduser --gecos "Test User,,," --disabled-password testuser
Adding user `testuser' ...
Adding new group `testuser' (1000) ...
Adding new user `testuser' (1000) with group `testuser' ...
Creating home directory `/home/testuser' ...
Copying files from `/etc/skel' ...

$ echo 'testuser:TestPass123' | chpasswd
```

Its own output narrates the four things it did beyond creating the account: made a
matching group, allocated UID 1000 from the configured range, created the home
directory, and populated it from `/etc/skel`. Verifying rather than trusting it:

```bash
$ grep testuser /etc/passwd
testuser:x:1000:1000:Test User,,,:/home/testuser:/bin/bash

$ grep testuser /etc/group
testuser:x:1000:

$ getent shadow testuser | cut -c1-40
testuser:$y$j9T$q6L/dJqrQxRyjOi.bmjZf1$h    (truncated)

$ ls -la /home/testuser
drwxr-x--- 2 testuser testuser 4096 Sep  4 17:12 .
-rw-r--r-- 1 testuser testuser  220 Sep  4 17:12 .bash_logout
-rw-r--r-- 1 testuser testuser 3771 Sep  4 17:12 .bashrc
-rw-r--r-- 1 testuser testuser  807 Sep  4 17:12 .profile

$ id testuser
uid=1000(testuser) gid=1000(testuser) groups=1000(testuser)

$ su - testuser -c 'whoami; pwd; echo $SHELL'
testuser
/home/testuser
/bin/bash
```

The `$y$` prefix on the shadow entry is a yescrypt hash, so a real password was
set. The home directory is mode `drwxr-x---` and owned by `testuser`, with the
three dotfiles copied from `/etc/skel`. And `su -` actually works: the account is
complete and usable. *(The hash shown is for a throwaway account inside a
container that was destroyed at the end of this run.)*

### The contrast: bare `useradd`

```bash
$ useradd testuser2

$ grep testuser2 /etc/passwd
testuser2:x:1001:1001::/home/testuser2:/bin/sh

$ ls /home/ | tr '\n' ' '
testuser

$ passwd -S testuser2
testuser2 L 09/04/2026 0 99999 7 -1
```

Three defects in one account, and they are the entire point of the task:

1. **Shell is `/bin/sh`**, not `/bin/bash` — `useradd` ignored `DSHELL` from
   `/etc/adduser.conf` because it never reads that file.
2. **The home directory does not exist.** `/etc/passwd` claims
   `/home/testuser2`, but `ls /home/` lists only `testuser`. The path is
   recorded and was never created, so this user would land in a non-existent
   directory on login.
3. **`passwd -S` reports `L`** — locked. There is no usable password, so the
   account cannot be logged into at all.

### `useradd` done correctly

`useradd` is not broken — it does exactly and only what it is told:

```bash
$ useradd -m -s /bin/bash -c "Test User Three" -G sudo testuser3

$ grep testuser3 /etc/passwd
testuser3:x:1002:1002:Test User Three:/home/testuser3:/bin/bash

$ ls -la /home/testuser3
drwxr-x--- 2 testuser3 testuser3 4096 Sep  4 17:12 .
-rw-r--r-- 1 testuser3 testuser3  220 Jan  6  2022 .bash_logout
-rw-r--r-- 1 testuser3 testuser3 3771 Jan  6  2022 .bashrc
-rw-r--r-- 1 testuser3 testuser3  807 Jan  6  2022 .profile

$ id testuser3
uid=1002(testuser3) gid=1002(testuser3) groups=1002(testuser3),27(sudo)
```

`-m` creates and populates the home directory, `-s` sets the shell, `-c` sets the
GECOS comment, `-G sudo` adds a supplementary group. With those four flags the
result is equivalent to what `adduser` produced automatically.

One detail I noticed comparing the two listings: `testuser3`'s dotfiles are dated
`Jan 6 2022` — the mtimes from `/etc/skel` in the base image — while
`testuser`'s are dated today. `adduser` copies with fresh timestamps, `useradd -m`
preserves the originals. A small thing, but it is the sort of difference you only
see by running both.

### Cleanup

```bash
$ deluser --remove-home testuser2
Removing user `testuser2' ...
Warning: group `testuser2' has no more members.
Done.

$ cut -d: -f1 /etc/passwd | tail -5
nogroup
_apt
www-data
systemd-network
testuser
```

### Which is preferred on Ubuntu, and why

**`adduser`, for interactive administration.** It applies the policy in
`/etc/adduser.conf`, allocates the UID from the correct range, creates the home
directory with the right ownership and permissions, populates it from
`/etc/skel`, creates the matching user group, and prompts for a password — so the
account it produces is complete and immediately usable.

**`useradd`, inside scripts and Dockerfiles.** Precisely because it does only what
it is told, it is predictable: no config file changes its behaviour, no prompt can
block it, and its flags mean the same thing on every distribution. `adduser` does
not even exist on RHEL-family systems as the same tool. That combination of
"portable and non-interactive" is why almost every Dockerfile you read uses
`useradd -m -s ...` and never `adduser`.

---

## Task 3 — `journalctl`

### What it is

`journalctl` reads the systemd journal — a structured, indexed, binary log that
`systemd-journald` collects from unit stdout/stderr, syslog, the kernel ring
buffer and the audit subsystem. Because it is structured rather than plain text,
you can filter by unit, priority, boot or time range without parsing strings,
which is the fundamental difference from `grep`-ing `/var/log/`.

```bash
$ journalctl --disk-usage
Archived and active journals take up 16.0M in the file system.
```

### Query forms

| Command | Purpose |
|---|---|
| `journalctl -u nginx` | Only entries for one unit |
| `journalctl -f` | Follow live, like `tail -f` |
| `journalctl -n 20` | Last 20 entries |
| `journalctl -r` | Reverse order, newest first |
| `journalctl -b` | This boot only |
| `journalctl -k` | Kernel messages |
| `journalctl -p err` | Priority `err` and worse |
| `journalctl --since` / `--until` | Time ranges, incl. "5 minutes ago" |
| `journalctl -xe` | Annotated tail — the standard "what just broke" command |
| `journalctl -o json-pretty` | Full structured fields |
| `journalctl --vacuum-time=7d` | Maintenance: discard entries older than 7 days |

### Driving a real service

Rather than reading an empty journal, I started nginx so there would be genuine
entries to query:

```bash
$ systemctl enable --now nginx
$ curl -s localhost | head -4
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>

$ journalctl -u nginx --no-pager
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Starting A high performance web server and a reverse proxy server...
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Started A high performance web server and a reverse proxy server.
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Stopping A high performance web server and a reverse proxy server...
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: nginx.service: Deactivated successfully.
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Stopped A high performance web server and a reverse proxy server.
```

Each line carries the timestamp, the container hostname, and the emitting process
with its PID — `systemd[1]` here, because it is systemd narrating the unit's
lifecycle rather than nginx itself.

### Diagnosing a real failure from the journal alone

I broke the config deliberately, then used only the journal to find out why:

```bash
$ sed -i '1i this_is_invalid;' /etc/nginx/nginx.conf && head -2 /etc/nginx/nginx.conf
this_is_invalid;
user www-data;

$ systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.

$ journalctl -u nginx -n 20 --no-pager | tail -6
Sep 04 17:12:35 4f1eb9c1623d nginx[665]: nginx: [emerg] unknown directive "this_is_invalid" in /etc/nginx/nginx.conf:1
Sep 04 17:12:35 4f1eb9c1623d nginx[665]: nginx: configuration file /etc/nginx/nginx.conf test failed
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: nginx.service: Failed with result 'exit-code'.
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Failed to start A high performance web server and a reverse proxy server.
```

This is exactly why the journal is useful. Two different programs' accounts of the
same event are interleaved in one stream: **nginx** says what was wrong
(`[emerg] unknown directive "this_is_invalid" in /etc/nginx/nginx.conf:1` — with
the file and line number), and **systemd** says what it did about it
(`Failed with result 'exit-code'`). `systemctl status` alone would have told me
the unit failed; only the journal told me *why*.

`journalctl -xe` adds the `-x` explanatory annotations:

```bash
$ journalctl -xe --no-pager | tail -12
░░ An ExecStartPre= process belonging to unit nginx.service has exited.
░░ The process' exit code is 'exited' and its exit status is 1.
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: nginx.service: Failed with result 'exit-code'.
░░ Subject: Unit failed
░░ The unit nginx.service has entered the 'failed' state with result 'exit-code'.
Sep 04 17:12:35 4f1eb9c1623d systemd[1]: Failed to start A high performance web server and a reverse proxy server.
░░ Subject: A start job for unit nginx.service has failed
░░ A start job for unit nginx.service has finished with a failure.
░░ The job identifier is 314 and the job result is failed.
```

The `░░` lines are systemd's catalogue entries. Note it identifies the failing
step as `ExecStartPre=` — nginx's unit runs `nginx -t` before starting, which is
what actually caught the bad directive.

### Recovery

```bash
$ sed -i '/this_is_invalid;/d' /etc/nginx/nginx.conf && head -2 /etc/nginx/nginx.conf
user www-data;
worker_processes auto;

$ nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

$ systemctl restart nginx && systemctl is-active nginx
active
```

### Structured output

The same entry as JSON shows what is really stored per record:

```bash
$ journalctl -u nginx -o json-pretty --no-pager | head -18
{
	"MESSAGE_ID" : "7d4958e842da4a758f6c1cdc7b36dcc5",
	"INVOCATION_ID" : "67131c48b130462c87fe125002da9717",
	"_SYSTEMD_SLICE" : "-.slice",
	"CODE_FUNC" : "job_emit_start_message",
	"_PID" : "1",
	"CODE_FILE" : "src/core/job.c",
	"_COMM" : "systemd",
	"_TRANSPORT" : "journal",
	"JOB_TYPE" : "start",
	"_SYSTEMD_UNIT" : "init.scope",
	"_CMDLINE" : "/sbin/init",
	"_UID" : "0",
```

Fields prefixed with `_` are *trusted* — journald recorded them itself from the
kernel and cannot be forged by the logging process. That is the security property
a plain text log cannot offer, and it is why filters like `-u` are reliable.

The captured unit log is saved as
[`nginx-journal.log`](./nginx-journal.log) (18 lines).

---

## Task 4 — Command cheat sheet

Every command below was actually run; the full transcript with all output is in
[`../logs/01-linux.log`](../logs/01-linux.log). Selected results with what they
told me:

### Navigation and inspection

| Command | Purpose |
|---|---|
| `pwd` | Print working directory |
| `ls -lahi` | Long, all, human sizes, with inode numbers |
| `cd -` | Return to the previous directory (uses `$OLDPWD`) |
| `tree -L 2` | Directory tree, depth-limited |
| `stat` | Full inode metadata |
| `file` | Identify content type, not extension |
| `which` / `type` | Locate a binary / reveal what a name really is |

```bash
$ which bash; type cd
/usr/bin/bash
cd is a shell builtin
```

That pair is more instructive than it looks: `which bash` finds a file on disk,
but `type cd` reveals `cd` is a **shell builtin** with no file at all — which is
why `which cd` finds nothing and why `cd` cannot be run via `xargs` or `find -exec`.

### Files and directories

```bash
$ cp -rv x/ x-backup/
'x/' -> 'x-backup/'
'x/y' -> 'x-backup/y'
'x/y/z' -> 'x-backup/y/z'

$ find /etc -name "*.conf" -size +10k | head
/etc/fonts/conf.avail/65-fonts-persian.conf
/etc/fonts/conf.avail/30-metric-aliases.conf

$ df -hT
Filesystem     Type     Size  Used Avail Use% Mounted on
overlay        overlay  911G  4.2G  861G   1% /
tmpfs          tmpfs     64M     0   64M   0% /dev
tmpfs          tmpfs    3.9G   32K  3.9G   1% /run
/dev/vda1      ext4     911G  4.2G  861G   1% /etc/hosts
```

`df -hT` is a good demonstration of container storage: `/` is an **overlay**
filesystem, `/dev` and `/run` are `tmpfs` (the `--tmpfs` flags from the run
command), and `/etc/hosts` is bind-mounted from the VM's `ext4` disk, which is why
it shows a different filesystem from the directory containing it.

### Viewing and text processing

```bash
$ wc -l /etc/passwd
24 /etc/passwd

$ cut -d: -f7 /etc/passwd | sort | uniq -c
      2 /bin/bash
      1 /bin/sync
     21 /usr/sbin/nologin
```

That one pipeline is a genuinely useful security check. Of 24 accounts, **21 have
`/usr/sbin/nologin`** as their shell — they are service accounts that exist to own
files and run daemons, and deliberately cannot be logged into. Only 2 have a real
shell (`root` and `testuser`). If a service account ever showed `/bin/bash`, that
would be worth investigating.

```bash
$ ps aux | awk '{print $1, $11}' | head
USER COMMAND
root /sbin/init
root /lib/systemd/systemd-journald
message+ @dbus-daemon
root /lib/systemd/systemd-logind
root nginx:
www-data nginx:
www-data nginx:
www-data nginx:
www-data nginx:

$ sed -n '1,5p' /etc/passwd
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
```

`awk '{print $1, $11}'` selects the user and command columns; `sed -n '1,5p'`
prints an explicit line range. `ps` confirms `/sbin/init` is PID 1's command, and the user column is
informative in itself: the nginx **master** process runs as `root` (it must, to
bind port 80) while its four **workers** dropped to the unprivileged `www-data`
user. That privilege separation is visible for free in the output.

### Permissions and identity

```bash
$ chmod 750 renamed.txt && ls -l renamed.txt
-rwxr-x--- 1 root root 0 Sep  4 17:13 renamed.txt

$ chmod +x renamed.txt && ls -l renamed.txt
-rwxr-x--x 1 root root 0 Sep  4 17:13 renamed.txt

$ chown root:root renamed.txt && ls -l renamed.txt
-rwxr-x--x 1 root root 0 Sep  4 17:13 renamed.txt

$ umask; id; groups; whoami
0022
uid=0(root) gid=0(root) groups=0(root)
root
root
```

Comparing those two mode strings taught me something I had wrong. `750` gives
`-rwxr-x---`: no permissions at all for "other". Running `chmod +x` then produced
`-rwxr-x--x` — it **added execute for "other"**, making the file
world-executable. That is because `+x` with no scope letter means `a+x` (all of
user, group and other), not "just the owner". If I actually wanted owner-only I
would have to write `chmod u+x`. This is a real trap: `chmod +x script.sh` is
typed reflexively, and on a file with a restrictive mode it quietly widens
access.

The `chown root:root` was a genuine no-op — the file was already owned by
`root:root`, so the mode string is unchanged from the line above. `umask 0022`
means new files default to `644` and new directories to `755`.

### Processes and system state

```bash
$ uptime; free -h
 17:13:11 up 10 min,  0 users,  load average: 0.00, 0.08, 0.05
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       688Mi       3.2Gi       0.0Ki       3.9Gi       6.9Gi
Swap:          1.0Gi          0B       1.0Gi

$ sleep 300 & jobs; pkill -f "sleep 300"
[1]+  Running                 sleep 300 &

$ systemctl list-units --type=service --state=running --no-pager | head
  UNIT                     LOAD   ACTIVE SUB     DESCRIPTION
  dbus.service             loaded active running D-Bus System Message Bus
  nginx.service            loaded active running A high performance web server and a reverse proxy server
  systemd-journald.service loaded active running Journal Service
  systemd-logind.service   loaded active running User Login Management
...
4 loaded units listed.
```

`free -h` reports **7.7 GiB** — the memory of the Docker VM, not the Mac, which is
the correct thing for a container to see. `0 users` is right too: nobody is logged
in, commands arrive via `docker exec`. The `jobs`/`pkill` pair demonstrates
background job control, and `systemctl list-units` shows the four services systemd
is actually supervising, including the nginx from Task 3.

### Archives, packages, transfer

```bash
$ tar -czvf lab.tgz links-lab/ && ls -lh lab.tgz && tar -tzf lab.tgz | head
links-lab/
links-lab/broken
links-lab/mydir/
links-lab/original.txt
links-lab/hardlink.txt
-rw-r--r-- 1 root root 277 Sep  4 17:13 lab.tgz

$ apt list --installed 2>/dev/null | wc -l
217

$ curl -sI https://github.com | head -3
HTTP/2 200
server: github.com
```

`-czvf` = create, gzip, verbose, file. The archive is **277 bytes** for five
entries because the content is tiny and gzip is effective — and note `broken`, a
dangling symlink, archived without complaint: `tar` stores the link target string,
not the file it fails to point at. `217` packages are installed — a deliberately small number, which is what the
`--no-install-recommends` flag in the Dockerfile bought us.

---

## Files in this folder

| File | Contents |
|---|---|
| [`lab-environment/Dockerfile`](./lab-environment/Dockerfile) | The Ubuntu 22.04 + systemd lab image |
| [`links-lab/`](./links-lab) | Artefacts from Task 1, copied out of the container with `docker cp` — including the surviving hard link and the deliberately broken symlink |
| [`nginx-journal.log`](./nginx-journal.log) | Captured `journalctl -u nginx` output (18 lines) |
| [`../logs/01-linux.log`](../logs/01-linux.log) | Full raw transcript — 97 commands, 686 lines |
