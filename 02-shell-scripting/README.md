# Part 02 — Shell Scripting

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Script:** [`sysinfo.sh`](./sysinfo.sh) — 84 lines
**Executed on:** twice — inside the Ubuntu 22.04 container (the graded run) and
natively on macOS 26.6.2 (arm64), to prove portability

---

## What the script does

`sysinfo.sh` is one script that satisfies all ten stated requirements. It gathers
system information into variables, prompts me for three pieces of input, prints a
formatted report, then creates a directory and two files and writes the process
and disk data into them using output redirection.

## Requirement mapping

Every requirement, the mechanism I used, and the actual line in `sysinfo.sh`:

| # | Requirement | Mechanism | Line(s) |
|---|---|---|---|
| 1 | Print current date | `date` inside command substitution | 12 |
| 2 | Print hostname | `hostname` | 13 |
| 3 | Print username | `whoami` | 14 |
| 4 | Print disk usage | `df -h` | 48, 76 |
| 5 | Print running processes | `ps aux` | 55, 74 |
| 6 | Use variables | `name=value` assignment and `"$name"` expansion | 12–15, 25, 61–62 |
| 7 | Take user input | `read -p` | 22, 23, 24 |
| 8 | Create a directory | `mkdir -p` | 59 |
| 9 | Create a file | `touch` | 63 |
| 10 | Redirect output to a file | `>` to overwrite, `>>` to append | 68 (`>`), 69–74 (`>>`), 76 (`>`) |

A bonus eleventh mechanism is on line 25:

```bash
report_dir=${report_dir:-system-report}
```

`${var:-default}` substitutes a default when the variable is unset **or empty**,
so pressing Enter at the third prompt gives `system-report` instead of an empty
directory name. This is what makes the script safe to drive from a pipe.

---

## The real runs

The script was run twice, on two different operating systems, with input supplied
from a pipe so both runs are reproducible rather than depending on me typing:

```bash
# 1. In the Ubuntu 22.04 container - this is the run that produced system-report/
$ printf '%s\n%s\n\n' 'THRISHAL DOMA' '24BCS10097' \
    | docker exec -i linux-lab bash -lc 'cd /root && ./sysinfo.sh'

# 2. Natively on the macOS host - produced macos-report/
$ printf '%s\n%s\nmacos-report\n' 'THRISHAL DOMA' '24BCS10097' | ./sysinfo.sh
```

The empty third line in the first run is deliberate: it exercises the
`${report_dir:-system-report}` default. Full unedited transcripts are in
[`run-output.txt`](./run-output.txt) (container) and
[`run-output-macos.txt`](./run-output-macos.txt) (macOS).

Below is the **macOS** run, because its `df -h` and `ps aux` output is the more
interesting of the two. The container run follows in the comparison section.

```
==============================================
        SYSTEM INFORMATION SCRIPT
==============================================


----------------------------------------------
 SUBMITTED BY
----------------------------------------------
Name          : THRISHAL DOMA
Enrollment No : 24BCS10097

----------------------------------------------
 SYSTEM DETAILS
----------------------------------------------
Current Date  : Friday, 04 September 2026 - 22:07:04
Hostname      : THRISHALs-MacBook-Pro.local
Username      : thrishaldoma
Kernel        : 25.6.0

----------------------------------------------
 DISK USAGE (df -h)
----------------------------------------------
Filesystem        Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1   926Gi    12Gi   789Gi     2%    459k  4.3G    0%   /
devfs            203Ki   203Ki     0Bi   100%     702     0  100%   /dev
/dev/disk3s6     926Gi   4.0Gi   789Gi     1%       4  8.3G    0%   /System/Volumes/VM
/dev/disk3s2     926Gi   8.5Gi   789Gi     2%    1.5k  8.3G    0%   /System/Volumes/Preboot
/dev/disk3s4     926Gi   2.7Mi   789Gi     1%      62  8.3G    0%   /System/Volumes/Update
/dev/disk1s2     550Mi   6.0Mi   531Mi     2%       1  5.4M    0%   /System/Volumes/xarts
/dev/disk1s1     550Mi   5.9Mi   531Mi     2%      31  5.4M    0%   /System/Volumes/iSCPreboot
/dev/disk1s3     550Mi   2.3Mi   531Mi     1%     106  5.4M    0%   /System/Volumes/Hardware
/dev/disk3s5     926Gi   111Gi   789Gi    13%    1.1M  8.3G    0%   /System/Volumes/Data
map auto_home      0Bi     0Bi     0Bi   100%       0     0     -   /System/Volumes/Data/home

----------------------------------------------
 RUNNING PROCESSES (first 10)
----------------------------------------------
USER               PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
_windowserver      592  25.2  0.4 436556384 107936   ??  Ss   27Aug26 490:58.08 .../Resources/WindowServer -daemon
root             68409  21.5  0.1 435399408  36912   ??  Ss    7:54PM   0:00.59 .../XprotectService
thrishaldoma     70008  17.7  5.7 1951623216 1440976   ??  S     9:35PM   4:38.87 .../Google Chrome Helper (Renderer)
root               560  14.4  0.1 435405952  13824   ??  Ss   27Aug26   7:52.33 /usr/libexec/opendirectoryd
thrishaldoma     96298   8.0  1.0 487334272 245776   ??  S    Wed05PM  62:45.75 .../Google Chrome Helper --type=gpu-process
thrishaldoma     70967   5.3  2.2 440935776 549712 s000  S+    9:55PM   0:36.52 claude
thrishaldoma      7594   5.1  0.6 436209680 141520   ??  S    Wed09PM   1:09.63 .../Terminal.app/Contents/MacOS/Terminal
thrishaldoma     96290   3.4  2.4 537504224 593760   ??  S    Wed05PM  49:23.83 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
_coreaudiod        607   3.1  0.1 435317984  26880   ??  Ss   27Aug26 106:30.68 /usr/sbin/coreaudiod
_trustd            601   2.2  0.0 435410672  12272   ??  Ss   27Aug26   1:49.52 /usr/libexec/trustd

[+] Directory created : system-report
[+] File created      : system-report/process.log

[+] Running processes saved to  : system-report/process.log
[+] Disk usage saved to         : system-report/disk-usage.log
[+] Lines written to process.log:      564

==============================================
 Script completed successfully.
==============================================
```

*(The long Chrome and system process paths are abbreviated with `...` above purely
so the table stays readable. The unabridged lines are in `run-output.txt` and
`system-report/process.log`.)*

---

## The files the script created

The container run (the graded one) produced:

```bash
$ docker exec linux-lab bash -lc 'wc -l /root/system-report/process.log'
29 /root/system-report/process.log
```

`process.log` opens with the five header lines written by `echo`, then the full
`ps aux` dump appended after them:

```
===== PROCESS REPORT =====
Generated : Friday, 04 September 2026 - 17:17:13
Host      : 4f1eb9c1623d
User      : root
Student   : THRISHAL DOMA (24BCS10097)

USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.1  18704  9700 ?        Ss   17:10   0:00 /sbin/init
root          23  0.0  0.1  48084 14340 ?        S<s  17:10   0:00 /lib/systemd/systemd-journald
message+     343  0.0  0.0   7764  3752 ?        Ss   17:12   0:00 @dbus-daemon --system ...
root         345  0.0  0.0  15300  6848 ?        Ss   17:12   0:00 /lib/systemd/systemd-logind
root         715  0.0  0.0  55076  2288 ?        Ss   17:12   0:00 nginx: master process /usr/sbin/nginx
www-data     716  0.0  0.0  55404  3256 ?        S    17:12   0:00 nginx: worker process
```

`disk-usage.log` holds the `df -h` table:

```
Filesystem      Size  Used Avail Use% Mounted on
overlay         911G  4.2G  861G   1% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           3.9G   32K  3.9G   1% /run
tmpfs           3.9G     0  3.9G   0% /run/lock
/dev/vda1       911G  4.2G  861G   1% /etc/hosts
```

### What running it on both systems revealed

The same script, unmodified, on two operating systems:

| | Container (`system-report/`) | macOS host (`macos-report/`) |
|---|---|---|
| `Hostname` | `4f1eb9c1623d` (container ID) | `THRISHALs-MacBook-Pro.local` |
| `Username` | `root` | `thrishaldoma` |
| `Kernel` (`uname -r`) | `7.0.12-linuxkit` | `25.6.0` (Darwin) |
| `process.log` lines | **29** | **564** |
| `df -h` root filesystem | `overlay` | `/dev/disk3s1s1` (APFS) |

The line counts are the striking part. The container has **29** lines because a
container runs almost nothing — PID 1, journald, dbus, logind and five nginx
processes. The Mac has **564**, because a desktop OS runs hundreds of daemons,
Chrome helpers and user applications. Seeing 29 versus 564 from one identical
script made the "a container is a process namespace, not a virtual machine" point
far more concretely than a definition would have.

It also validated the portability choices: because the script avoids
`ps aux --sort=-%mem` and `uptime -p`, it ran identically under BSD userland and
GNU coreutils with no changes at all.

## `>` versus `>>` — the difference that matters

This is the single most important thing in the redirection section, and the file
I produced demonstrates it:

| Operator | Behaviour | Where I used it |
|---|---|---|
| `>` | **Truncates** the file to zero length, then writes. Creates it if absent. | Line 68 starts `process.log` fresh; line 76 writes `disk-usage.log` in one shot |
| `>>` | **Appends** to the end. Creates it if absent. Never destroys existing content. | Lines 69–74 add the header lines and then the `ps aux` output |

The proof is in the numbers. Lines 68–74 run seven redirections at the same file.
If they had all used `>`, each would have wiped the last and `process.log` would
contain only the final `ps aux` output. Instead it has all five header
lines, a blank line, and the whole process table — 29 lines in the container run
and 564 in the macOS run. Only the first line uses `>` —
deliberately, so that re-running the script produces a clean report rather than
appending to a stale one forever.

That last point is the practical rule I took from this: use `>` once at the top of
a generated file to reset it, then `>>` for everything after. Using `>` throughout
silently discards data, and using `>>` throughout makes a log that grows without
bound across runs.

---

## Portability: why the script avoids some obvious flags

I deliberately did **not** use `uptime -p` or `ps aux --sort=-%mem`, even though
both are tidier. Those are GNU extensions. macOS ships a BSD userland where
`uptime` has no `-p` and `ps` rejects `--sort`, so the script would have failed on
the host it was written on. `ps aux | head -11` and plain `df -h` behave the same
under BSD and GNU, so this one script runs unmodified on both macOS bash and the
Linux container. Writing it that way was a choice, not an accident — and it is the
same reasoning that later made me run the Linux-only tasks in a container instead
of trying to fake them on macOS.

---

## Files in this folder

| File | Contents |
|---|---|
| `sysinfo.sh` | The script (executable, `#!/bin/bash` on line 1) |
| `run-output-macos.txt` | Real run on the **macOS host**, with folder name `macos-report` |
| `run-output.txt` | Real run **inside the Ubuntu container** (the graded run) |
| `system-report/process.log` | 29 lines from the container run: header written with `>` then `>>`, plus full `ps aux` |
| `system-report/disk-usage.log` | Container `df -h` output, written with `>` |
| `macos-report/process.log` | 564 lines from the macOS run — same script, different OS |
| `macos-report/disk-usage.log` | macOS `df -h` output |
| [`../logs/02-shell.log`](../logs/02-shell.log) | Full raw transcript of the phase |
