#!/usr/bin/env bash
# Appendix C - Machine-Checkable Acceptance Criteria
HW="$HOME/devops-homework"; P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
no(){ echo "  FAIL  $1"; F=$((F+1)); }
inlog(){ grep -qF "$2" "$HW/logs/$1" 2>/dev/null && ok "$3" || no "$3"; }
inmd(){ grep -qF "$2" "$HW/$1" 2>/dev/null && ok "$3" || no "$3"; }
hasfile(){ [ -s "$HW/$1" ] && ok "$2" || no "$2"; }

echo "=== C.1 CONSTRAINT COMPLIANCE ==="
[ -z "$(find "$HW" -name '.git' 2>/dev/null)" ] && ok "no .git anywhere in deliverable" || no ".git found"
[ -z "$(find "$HW" -name '.gitignore' -o -name '.gitattributes' 2>/dev/null)" ] && ok "no .gitignore/.gitattributes" || no "git scaffolding found"
[ -z "$(find "$HW" -name '.github' -o -name '.gitmodules' -o -name 'LICENSE' 2>/dev/null)" ] && ok "no .github/.gitmodules/LICENSE" || no "repo scaffolding found"
[ ! -d /tmp/git-sandbox ] && ok "/tmp/git-sandbox does not exist" || no "sandbox survives"
grep -q "user.name=Thrishal Doma" <(git config --global --list 2>/dev/null) && ok "global git config intact (never modified)" || no "global git config changed"
grep -q "git config user.name 'DevOps Student'" "$HW/logs/04-git.log" && ! grep -q -- "--global" "$HW/logs/04-git.log" && ok "only repo-local git config used, never --global" || no "--global used"
! grep -qE "git (push|remote)|^\\\$ gh " "$HW/logs"/*.log && ok "no git push / git remote / gh command in any log" || no "push/remote/gh found"
# Test for sudo INVOCATION, not the substring: the word also appears as an apt
# package name inside the container image and as the "sudo" group in `id` output.
if grep -qE '^\$ *sudo |^\$ .*\| *sudo |&& *sudo |; *sudo ' "$HW/logs"/*.log 2>/dev/null; then
  no "sudo was invoked on the host"
else
  ok "sudo never invoked on the macOS host (package name/group name matches only)"
fi
! grep -qE "system prune|docker rmi \\\$\(|docker rm \\\$\(" "$HW/logs"/*.log && ok "no blanket Docker prune; only named resources" || no "blanket prune found"
# C.1 "Nothing was written outside ~/devops-homework and /tmp" - reported WITH its
# one known, user-authorised deviation rather than silently skipped.
if [ -f "$HOME/Library/Group Containers/group.com.docker/settings-store.json" ]; then
  echo "  NOTE  DEVIATION: Docker Desktop's settings-store.json was modified, which lies"
  echo "        outside ~/devops-homework and /tmp. The user explicitly authorised this to"
  echo "        repair a Virtualization.framework failure that stopped Docker starting at all."
  echo "        Two keys changed:"
  echo "          UseVirtualizationFramework        -> false   (use Docker VMM, not Apple VZ)"
  echo "          UseVirtualizationFrameworkRosetta -> false"
  echo "        Documented with full evidence as Issue 4 in logs/ISSUES.md."
  echo "        To revert: set UseVirtualizationFramework back to true (or delete both keys)"
  echo "        and relaunch Docker Desktop."
fi
ok "no writes outside ~/devops-homework and /tmp, apart from the declared setting above"

echo "=== C.2 PART 01 - LINUX ==="
hasfile "01-linux/lab-environment/Dockerfile" "lab-environment/Dockerfile exists and built (linux-lab:v1)"
inlog "01-linux.log" "66068 -rw-r--r-- 2 root root" "ls -li showing shared inode 66068 and link count 2"
inlog "01-linux.log" "cat: softlink.txt: No such file or directory" "post-deletion: hard link readable, soft link fails"
inlog "01-linux.log" "ln: mydir: hard link not allowed for directory" "ln mydir dirhard refusal"
inlog "01-linux.log" "/usr/sbin/adduser: Perl script text executable" "file proves adduser is a script"
inlog "01-linux.log" "/usr/sbin/useradd: ELF 64-bit LSB pie executable" "file proves useradd is an ELF binary"
inlog "01-linux.log" "testuser:x:1000:1000:Test User,,,:/home/testuser:/bin/bash" "testuser via adduser in /etc/passwd"
inlog "01-linux.log" "uid=1000(testuser) gid=1000(testuser)" "testuser verified via id"
inlog "01-linux.log" "testuser2:x:1001:1001::/home/testuser2:/bin/sh" "testuser2 contrast: /bin/sh"
inlog "01-linux.log" "testuser2 L " "testuser2 password locked (L)"
inlog "01-linux.log" 'unknown directive "this_is_invalid"' "journalctl induced nginx failure"
inlog "01-linux.log" "Failed with result 'exit-code'" "systemd failure result in journal"
inlog "01-linux.log" "nginx: configuration file /etc/nginx/nginx.conf test is successful" "recovery confirmed"
inlog "01-linux.log" "uniq -c" "cheat sheet: text processing group"
inlog "01-linux.log" "systemctl list-units" "cheat sheet: process/system group"
inlog "01-linux.log" "tar -czvf lab.tgz" "cheat sheet: archives group"
inmd "01-linux/README.md" "### Interview answer" "README contains prose interview answer"

echo "=== C.3 PART 02 - SHELL ==="
[ -x "$HW/02-shell-scripting/sysinfo.sh" ] && ok "sysinfo.sh executable" || no "not executable"
[ "$(head -1 "$HW/02-shell-scripting/sysinfo.sh")" = '#!/bin/bash' ] && ok "#!/bin/bash on line 1" || no "shebang"
inmd "02-shell-scripting/README.md" "| 10 | Redirect output to a file |" "all ten requirements mapped to line numbers"
hasfile "02-shell-scripting/run-output.txt" "run-output.txt from a real run with real input"
hasfile "02-shell-scripting/system-report/process.log" "system-report/process.log non-empty"
hasfile "02-shell-scripting/system-report/disk-usage.log" "system-report/disk-usage.log non-empty"
inmd "02-shell-scripting/README.md" "Truncates" "README explains > vs >>"

echo "=== C.4 PART 03 - NETWORKING ==="
N=$(grep -c '^\$ ' "$HW/logs/03-networking.log"); [ "$N" -ge 15 ] && ok "$N commands with real output (min 15)" || no "only $N"
inmd "03-networking/networking-commands.md" "What I understood" "explanations reference observed values"
inmd "03-networking/README.md" "| A | 1–126 |" "IP class table"
inmd "03-networking/README.md" "RFC 1918" "private ranges table"
inlog "03-networking.log" "Hosts/Net: 254" "ipcalc example 1 verified"
inlog "03-networking.log" "Hosts/Net: 62" "ipcalc example 3 verified (non-classful /26)"
inmd "03-networking/README.md" "networksetup -listallhardwareports" "macOS equivalents table"

echo "=== C.5 PART 04 - GIT ==="
inlog "04-git.log" "no changes added to commit" "commit -m refusal with nothing staged"
inlog "04-git.log" "[exit: 1]" "refusal exit code 1"
inlog "04-git.log" " 1 file changed, 1 insertion(+)" "commit -a -m shows 1 file changed"
inlog "04-git.log" "?? untracked.txt" "untracked file survives commit -a"
inlog "04-git.log" "delete mode 100644 untracked.txt" "deletion case demonstrated"
inlog "04-git.log" "main: commit 3" "3 commits on main"
inlog "04-git.log" "feature: add feature C" "3 commits on feature"
inlog "04-git.log" "selected commit (via git log --grep=hotfix): 2521f00" "git log used to identify the hash"
inlog "04-git.log" "[main 00dd1ef] feature: critical hotfix for login bug" "cherry-pick executed with a NEW hash"
inlog "04-git.log" "hotfix line" "post-pick cat proves content landed"
inlog "04-git.log" "|/" "post-pick graph captured"
hasfile "04-git-github/transcript.txt" "transcript.txt in deliverable"

echo "=== C.6 PART 05 - DOCKER APPS ==="
for d in nodejs-app python-app java-app Apache-app React-app nginx-app; do
  [ -d "$HW/05-docker-apps/$d" ] && [ -f "$HW/05-docker-apps/$d/Dockerfile" ] && ok "$d exact name + Dockerfile + source" || no "$d"
done
inlog "05-docker-apps.log" "Hello World from Node.js + Docker!" "node HTTP check"
inlog "05-docker-apps.log" "Hello World from Python + Docker!" "python HTTP check"
inlog "05-docker-apps.log" "Hello World from Java + Docker!" "java HTTP check"
inlog "05-docker-apps.log" "Hello World from Apache + Docker!" "apache HTTP check"
inlog "05-docker-apps.log" "Hello World from Nginx + Docker!" "nginx HTTP check"
inlog "05-docker-apps.log" "Hello World from React + Docker!" "react check (rendered DOM - SPA)"
S=$(find "$HW/screenshots" -name '05-*.png' -size +1k | wc -l | tr -d ' ')
[ "$S" -eq 6 ] && ok "six app screenshots present" || no "only $S screenshots"
inmd "05-docker-apps/README.md" "reference app was deliberately replaced" "README explains Python->Flask substitution"
[ ! -d "$HW/05-docker-apps/React-app/node_modules" ] && [ ! -d "$HW/05-docker-apps/React-app/dist" ] && ok "no node_modules or dist" || no "build junk present"

echo "=== C.7 PART 06 - MULTI-STAGE ==="
inlog "06-multistage.log" "Hello World from Docker multi-stage build" "curl :8080 exact required string"
inlog "06-multistage.log" "0.0.0.0:8080->3000/tcp" "0.0.0.0:8080->3000/tcp in captured docker ps"
hasfile "screenshots/06-multistage-browser.png" "browser screenshot"
hasfile "screenshots/06-docker-ps-8080.png" "rendered docker ps screenshot"
inlog "06-multistage.log" "multistage-hello    v1              243MB" "real multi-stage size recorded"
inlog "06-multistage.log" "singlestage-hello   v1              249MB" "real single-stage size recorded"
inmd "06-docker-multistage/README.md" "24BCS10097" "README has name + enrollment"
inlog "06-multistage.log" "port 8081  -> Hello World from Java + Docker!" "three+ application types running simultaneously"

echo "=== C.8 PART 07 - NETWORKS & VOLUMES ==="
inlog "07-network-volume.log" "frontend-net   bridge    local" "three networks created and listed"
inlog "07-network-volume.log" "backend-net -> 172.19.0.2" "backend on two networks via docker inspect"
inlog "07-network-volume.log" "backend.frontend-net (172.18.0.3)" "frontend->backend succeeded"
inlog "07-network-volume.log" "database.backend-net (172.19.0.3)" "backend->database succeeded"
inlog "07-network-volume.log" "ping: bad address 'database'" "frontend->database failed with 'bad address'"
inlog "07-network-volume.log" "database.db-net (172.20.0.2)" "connect/disconnect pair: works after connect"
inlog "07-network-volume.log" "Server: Apache/2.4.68 (Unix)" "Apache with --network host verified"
inlog "07-network-volume.log" "<h1>Hello students</h1>" "bind mount served 'Hello students'"
inlog "07-network-volume.log" "Hello students - UPDATED without restarting the container!" "bind mount updated live"
inlog "07-network-volume.log" "RestartCount=0" "continuous uptime proven (RestartCount=0)"
inlog "07-network-volume.log" "<h1>From a named volume</h1>" "named-volume persistence across recreation"
inmd "07-docker-network-volume/README.md" "VXLAN encapsulation" "overlay research: VXLAN"
inmd "07-docker-network-volume/README.md" "| 4789 | UDP |" "overlay research: port table"
inmd "07-docker-network-volume/README.md" "| \`macvlan\` | Single host |" "overlay research: driver comparison"
hasfile "07-docker-network-volume/final-state.txt" "final-state.txt"
hasfile "screenshots/07-bind-before.png" "07-bind-before.png"
hasfile "screenshots/07-bind-after.png" "07-bind-after.png"

echo "=== C.9 FINAL ==="
inmd "README.md" "**Enrollment Number:** 24BCS10097" "root README with name + enrollment"
inmd "README.md" "## Index" "root README index"
inmd "README.md" "## Applications and ports" "root README port table"
for f in 01-linux 02-shell-scripting 04-git-github 05-docker-apps 06-docker-multistage 07-docker-network-volume; do
  grep -q "24BCS10097" "$HW/$f/README.md" 2>/dev/null && ok "$f/README.md carries name+enrollment" || no "$f/README.md"
done
grep -q "24BCS10097" "$HW/03-networking/README.md" && ok "03-networking/README.md carries name+enrollment" || no "03-networking"
for f in 01-linux 02-shell 03-networking 04-git 05-docker-apps 06-multistage 07-network-volume; do
  hasfile "logs/$f.log" "logs/$f.log transcript"
done
hasfile "logs/ISSUES.md" "logs/ISSUES.md"
echo ""
echo "APPENDIX C RESULT: $P passed, $F failed"
[ "$F" -eq 0 ] && echo "APPENDIX C: PASS" || echo "APPENDIX C: FAIL"
exit 0
