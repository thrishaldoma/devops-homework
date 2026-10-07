#!/usr/bin/env bash
HW="$HOME/devops-homework"
PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
chkfile(){ [ -s "$HW/$1" ] && ok "$1" || no "$1 (missing or empty)"; }
chkdir(){  [ -d "$HW/$1" ] && ok "$1/" || no "$1/ (missing)"; }

echo "== NO-GIT RULE =="
if [ -z "$(find "$HW" -name '.git' -o -name '.gitignore' -o -name '.gitattributes' 2>/dev/null)" ]; then
  ok "no git artefacts anywhere in the deliverable"
else
  no "GIT ARTEFACTS FOUND:"; find "$HW" -name '.git' -o -name '.gitignore' -o -name '.gitattributes'
fi
[ -d /tmp/git-sandbox ] && no "/tmp/git-sandbox still exists" || ok "git sandbox removed"

echo "== STRUCTURE =="
for d in 01-linux 02-shell-scripting 03-networking 04-git-github \
         05-docker-apps 06-docker-multistage 07-docker-network-volume \
         screenshots logs; do chkdir "$d"; done
for d in nodejs-app python-app java-app Apache-app React-app nginx-app; do
  chkdir "05-docker-apps/$d"
  chkfile "05-docker-apps/$d/Dockerfile"
done

echo "== READMEs =="
for f in README.md 01-linux/README.md 02-shell-scripting/README.md \
         03-networking/networking-commands.md 04-git-github/README.md \
         05-docker-apps/README.md 06-docker-multistage/README.md \
         07-docker-network-volume/README.md; do chkfile "$f"; done

echo "== NAME AND ENROLLMENT PRESENT =="
for f in $(find "$HW" -name "*.md" -maxdepth 2); do
  grep -qi "enrollment" "$f" && ok "enrollment in $(basename $(dirname $f))/$(basename $f)" \
    || no "enrollment missing in ${f#$HW/}"
done

echo "== KEY ARTEFACTS =="
chkfile "02-shell-scripting/sysinfo.sh"
chkfile "02-shell-scripting/system-report/process.log"
chkfile "06-docker-multistage/Dockerfile"
chkfile "07-docker-network-volume/final-state.txt"
chkfile "04-git-github/transcript.txt"
chkfile "01-linux/lab-environment/Dockerfile"

echo "== LOGS =="
for f in logs/01-linux.log logs/02-shell.log logs/03-networking.log \
         logs/04-git.log logs/05-docker-apps.log logs/06-multistage.log \
         logs/07-network-volume.log; do chkfile "$f"; done

echo "== SCREENSHOTS =="
N=$(find "$HW/screenshots" -name "*.png" -size +1k 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -ge 6 ] && ok "$N non-trivial screenshots" || no "only $N screenshots (expected 8+)"

echo "== NO BUILD JUNK COMMITTED =="
[ -d "$HW/05-docker-apps/React-app/node_modules" ] && no "React-app/node_modules present - delete it" \
  || ok "no node_modules in deliverable"
[ -d "$HW/05-docker-apps/React-app/dist" ] && no "React-app/dist present - delete it" \
  || ok "no dist in deliverable"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "ACCEPTANCE: PASS" || echo "ACCEPTANCE: FAIL"
exit 0
