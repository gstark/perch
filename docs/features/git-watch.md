# Git Watch

A menu bar warning for local git work that could be lost. Git Watch scans this Mac and SSH hosts
for repositories. A badge with a count appears left of the CPU meter while a default branch has
commits that are not on its remote. Settings › Git Watch lists the machines and their roots.

## Invariants

- **One script for every machine.** `GitWatchScript` is POSIX `sh`. This Mac runs it with
  `/bin/sh -s`, and a remote host runs it with `ssh -o BatchMode=yes <host> sh -s`. Only
  `GitWatchMachine.shellCommand` knows the difference.
- **A scan never changes a repository.** The scan script runs no `fetch`, `push` or `gc`, and sets
  `GIT_OPTIONAL_LOCKS=0` so that `git` does not write the index. Only **Push to Remote** writes,
  and it never forces.
- **A remote scan never prompts.** `BatchMode=yes` turns a password or host-key question into a
  failure, which Settings shows. SSH trust stays in `~/.ssh`.
- **A failed scan keeps the last report.** The menu marks it `(stale)`. Work at risk stays at risk
  until a scan says otherwise.
- **Git Watch has no status item of its own.** It draws a badge into the CPU meter's item, and
  only while a scan runs or something is at risk. During a scan the badge is
  `arrow.triangle.2.circlepath`, and after it `arrow.triangle.branch`, each with the count. "Show
  in menu bar" hides the CPU item, so it hides the badge too.
- **The parsing stays in `Model/`.** `Tests/git-watch-test.swift` compiles `Model/` and the scanner,
  and runs the real script against repos it creates in a temporary folder.

## States

| State | Condition | At risk |
| --- | --- | --- |
| `ahead` | The upstream lacks commits that the branch has. | Yes |
| `noRemote` | The repo has no remote. | No |
| `unpushed` | A remote exists, but the branch has no upstream and no `<remote>/<branch>`. | Yes |
| `clean` | Nothing to push, or the repo has no commits yet. | No |
| `error` | `git` failed, or no default branch was found. | No |

The default branch is the one `origin/HEAD` names, then `main`, then `master`, then the checked-out
branch.

## Freshness

Git Watch compares with the remote-tracking ref and never fetches. A push from the same clone moves
that ref, so the warning clears at the next scan. A push of the same commits from a different clone
does not move it. That clone shows as `ahead` until you fetch in it.

## Schedule

A scan runs at launch, every 10 minutes, after the Mac wakes, and on **Scan Now**. All machines scan
at the same time, and a scan has a 60-second limit. Results stay in memory.

## The menu

While the badge shows, the CPU menu starts with **Git Watch: N Unpushed** (or **Git Watch:
Scanning…**). Its submenu lists the repos by machine, so the process list stays in reach.

Each repo row opens its own submenu:

- **Open in Finder**, or **Copy ssh Command** for a repo on a remote host.
- **Push to Remote** runs `GitWatchScript.push` on the repo's machine, through the same transport
  as the scan. It pushes the default branch to its upstream, or with `--set-upstream` to `origin`
  (else the first remote) when it has none. `GIT_TERMINAL_PROMPT=0` makes a credential question
  fail instead of hang. The HUD shows progress, then the result or git's rejection or error line.
  A successful push marks the repo clean at once, so the count drops before the next scan.
- **Ignore This Repository** adds it to the machine's ignore list. Settings lists the ignored repos
  of each machine, each with **Unignore**.

**Scan Now** is disabled while a scan runs.

## Settings

`gitWatch.machines` in settings.json holds every machine as `{host, roots, ignored}`. An empty host
is this Mac, which `GitWatchMachine.normalize` always keeps first. A host that starts with `-` or
holds a space is dropped, so it cannot become an ssh option.

## Requirements

- This Mac needs `/usr/bin/git`, which the Xcode command line tools provide.
- A remote host needs `sh`, `find` and `git`, and an SSH key that it accepts with no prompt.
