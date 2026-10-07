# Part 04 — Git / GitHub

**Name:** THRISHAL DOMA
**Enrollment No:** 24BCS10097
**Environment:** macOS 26.6.2 (arm64), git version 2.50.1 (Apple Git-155)

---

## A note on where this work was done

Both of these tasks genuinely need a real Git repository — you cannot demonstrate
`git commit -a -m` or `git cherry-pick` without commits to work on. But this
deliverable folder must not contain a repository, because a stray `.git`
directory inside it would turn into a broken nested repository the moment the
whole folder is committed.

So I built both labs under `/tmp/git-sandbox/`, captured every command and its
real output as plain text, and then deleted the sandbox entirely. What survives
here is the transcript in [`transcript.txt`](./transcript.txt) and this
write-up — no repository, no `.git`.

I also set my identity with **repo-local** `git config`, deliberately *not*
`git config --global`, so my own machine-wide Git identity was never modified:

```bash
$ git config user.name 'DevOps Student'
$ git config user.email 'student@example.com'
$ git config --local --list
core.repositoryformatversion=0
core.filemode=true
core.bare=false
core.logallrefupdates=true
core.ignorecase=true
core.precomposeunicode=true
user.name=DevOps Student
user.email=student@example.com
```

---

## Task 1 — `git commit -a -m` vs `git commit -m`

### The question

Both commands commit with a message written inline. The difference is entirely
about **what gets staged**, and the only way to see it is to set up a repository
where a tracked file has been modified *and* an untracked file exists, then try
both.

### Setting up the test

```bash
$ echo line1 > file1.txt && git add . && git commit -m 'initial commit'
[main (root-commit) da82eaf] initial commit
 1 file changed, 1 insertion(+)
 create mode 100644 file1.txt

$ echo modified >> file1.txt      # a TRACKED file, modified but not staged
$ echo new > untracked.txt        # a brand-new UNTRACKED file

$ git status -s
 M file1.txt
?? untracked.txt
```

The two-character status codes matter here. ` M` means file1.txt is modified in
the working tree but *not* staged (the blank first column is the index). `??`
means Git has never seen untracked.txt at all.

### Test 1 — plain `commit -m` with nothing staged is refused

```bash
$ git commit -m 'try without staging'
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   file1.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	untracked.txt

no changes added to commit (use "git add" and/or "git commit -a")
[exit: 1]
```

No commit was created and the exit code was **1**. `git commit -m` commits *the
index*, and the index was empty — my modification was only in the working tree.
Git even names both escape routes in the last line: `git add`, or `git commit -a`.

### Test 2 — `commit -a -m` stages tracked changes automatically

```bash
$ git commit -a -m 'commit with -a'
[main 2936db3] commit with -a
 1 file changed, 1 insertion(+)

$ git status -s
?? untracked.txt

$ git show --stat --oneline HEAD
2936db3 commit with -a
 file1.txt | 1 +
 1 file changed, 1 insertion(+)
```

This is the decisive result, and it says two things at once:

- **`1 file changed`** — the modification to file1.txt was staged and committed
  automatically. I never ran `git add`.
- **`?? untracked.txt` is still there after the commit** — `-a` did *not* pick up
  the new file. It was ignored completely.

Those two facts together are the whole answer: `-a` means "stage everything Git
is already tracking", not "stage everything in the directory".

### Test 3 — `-a` also handles deletions

A deletion of a tracked file is just another modification to a tracked path, so
`-a` should catch it too. It does:

```bash
$ git add untracked.txt && git commit -m 'track the new file'
[main 6d52c35] track the new file
 1 file changed, 1 insertion(+)
 create mode 100644 untracked.txt

$ rm untracked.txt && echo more >> file1.txt && git status -s
 M file1.txt
 D untracked.txt

$ git commit -a -m 'handles modifications and deletions'
[main 4413b31] handles modifications and deletions
 2 files changed, 1 insertion(+), 1 deletion(-)
 delete mode 100644 untracked.txt

$ git status -s
$ git log --oneline
4413b31 handles modifications and deletions
6d52c35 track the new file
2936db3 commit with -a
da82eaf initial commit
```

`2 files changed` and `delete mode 100644 untracked.txt` confirm the deletion was
staged automatically, and the empty `git status -s` afterwards shows a clean tree.

### Summary table

| Situation | `git commit -m` | `git commit -a -m` |
|---|---|---|
| Already staged with `git add` | Committed | Committed |
| Tracked file modified, unstaged | Ignored; commit aborts | Auto-staged and committed |
| Tracked file deleted, unstaged | Ignored | Auto-staged and committed |
| Brand-new untracked file | Ignored | **Still ignored** |
| Nothing to commit | Exit 1, "no changes added" | Exit 1, "nothing to commit" |

### What I took away from this

`-a` is a convenience for the common case where I have edited files that are
already under version control and want all of those edits in one commit. It is
not a shortcut for `git add -A`. The trap is that it looks like "commit
everything" but silently skips new files — so if I add a new source file and use
`git commit -a -m`, the commit builds fine on my machine and then fails for
everyone else, because the new file was never committed. That is why I would
still run `git status` before committing rather than trusting `-a` blindly.

---

## Task 2 — Cherry-pick

### The scenario

Three commits on `main`, then a `feature` branch with three more commits, one of
which is an urgent hotfix. The hotfix is needed on `main` **now**, but the other
two feature commits are unfinished and must not ship. That is precisely what
cherry-pick is for.

### Building the history

```bash
$ for i in 1 2 3; do echo "main change $i" >> main.txt; git add .; git commit -m "main: commit $i"; done
$ git checkout -b feature
$ echo 'feature A'    > featA.txt  && git add . && git commit -m 'feature: add feature A'
$ echo 'hotfix line'  > hotfix.txt && git add . && git commit -m 'feature: critical hotfix for login bug'
$ echo 'feature C'    > featC.txt  && git add . && git commit -m 'feature: add feature C'

$ git log --oneline --graph --all --decorate
* 2915ee8 (HEAD -> feature) feature: add feature C
* 2521f00 feature: critical hotfix for login bug
* 2c8dccc feature: add feature A
* 98e95e7 (main) main: commit 3
* d3750e2 main: commit 2
* bb63f1a main: commit 1
```

### Identifying the commit to pick

Rather than reading the hash off the screen by eye, I let `git log` find it:

```bash
$ git log --format=%h --grep="hotfix"
2521f00

$ git show 2521f00 --stat
commit 2521f00b815b7f93d6ed5d82767f0e48b0618425
Author: DevOps Student <student@example.com>
Date:   Fri Sep 4 22:04:29 2026 +0530

    feature: critical hotfix for login bug

 hotfix.txt | 1 +
 1 file changed, 1 insertion(+)
```

### Applying it to main

```bash
$ git checkout main
Switched to branch 'main'

$ ls                       # hotfix.txt is NOT here yet
main.txt

$ git cherry-pick 2521f00
[main 00dd1ef] feature: critical hotfix for login bug
 Date: Fri Sep 4 22:04:29 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 hotfix.txt
```

### Verifying it

```bash
$ ls                       # hotfix.txt has now appeared
hotfix.txt
main.txt

$ cat hotfix.txt
hotfix line

$ git log --oneline
00dd1ef feature: critical hotfix for login bug
98e95e7 main: commit 3
d3750e2 main: commit 2
bb63f1a main: commit 1

$ git log --oneline --graph --all --decorate
* 00dd1ef (HEAD -> main) feature: critical hotfix for login bug
| * 2915ee8 (feature) feature: add feature C
| * 2521f00 feature: critical hotfix for login bug
| * 2c8dccc feature: add feature A
|/
* 98e95e7 main: commit 3
* d3750e2 main: commit 2
* bb63f1a main: commit 1
```

### The four things this proves

1. **`hotfix.txt` now exists on `main`.** The `ls` immediately before the pick
   printed only `main.txt`; the `ls` immediately after printed `hotfix.txt` and
   `main.txt`. The change really landed.
2. **The commit message on `main` is identical** to the one on `feature` —
   "feature: critical hotfix for login bug". Cherry-pick reuses the original
   message and author date by default.
3. **The hash is different: `2521f00` on `feature` versus `00dd1ef` on `main`.**
   This is the important one. A commit hash covers the parent commit and the tree,
   and both of those differ on `main` — so cherry-pick **copies** the change into
   a brand-new commit object. It does not move or share the original commit. In
   the graph the two commits sit on separate lines of history with the same
   message, which is exactly what a copy looks like.
4. **`feature A` and `feature C` did not come across.** `git log` on `main` shows
   only the hotfix on top of the three original main commits. The unfinished work
   stayed on the branch, which was the entire objective.

### Cherry-pick vs merge vs rebase

| | What it moves | Effect on history | Hashes |
|---|---|---|---|
| `cherry-pick` | Only the commits you name | Copies them onto the current branch | New hashes |
| `merge` | The whole branch | Adds a merge commit joining both histories | Originals preserved |
| `rebase` | The whole branch | Replays it linearly onto a new base | All rewritten |

### Useful variations

| Flag | Purpose |
|---|---|
| `-x` | Appends "(cherry picked from commit ...)" to the message — worth using so the origin is traceable |
| `-n` | Applies the change to the working tree and index without committing, so you can amend it first |
| `--continue` | Resumes after you have resolved a conflict |
| `--abort` | Gives up and restores the branch to its pre-pick state |
| `A..B` | Picks a whole range of commits rather than one |

### What I took away from this

The mental model that made this click is that a commit is not a patch — it is a
snapshot plus a parent pointer. So a commit cannot be "moved" to another branch,
because its identity is partly *where it sits*. Cherry-pick therefore computes the
diff the commit introduced and reapplies it on top of the new branch, producing a
new commit. That also explains why cherry-picking can conflict: the surrounding
code on `main` may have changed since the original commit was written. And it
explains the standard warning about cherry-picking between long-lived branches —
you now have the same change under two hashes, and a later merge has to work that
out.

---

## Files in this folder

| File | Contents |
|---|---|
| `README.md` | This write-up |
| `transcript.txt` | Complete unedited transcript of every Git command run, with real output |
| [`../logs/04-git.log`](../logs/04-git.log) | The same transcript in the phase log |

**No `.git` directory exists in this folder or anywhere in the deliverable.** The
sandbox at `/tmp/git-sandbox` was deleted after the transcript was captured.
