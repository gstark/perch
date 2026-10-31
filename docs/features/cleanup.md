# Cleanup

A list of build folders that projects can rebuild, such as `node_modules`, `target` and `.build`.
**Clean Up Projects…** in the CPU menu's Startup Disk section opens the window. You choose the
folders to walk, then press **Scan**. The list shows each project's build folders and the space
that removing them gives back, the most space first.

Each row's title is the build items that go, such as `.venv` or `tmp/cache, log/*.log`. The
project path sits in the subtitle, so the row never reads as the whole project. The button names
what it moves, such as **Trash .venv** or **Trash 2 items**.

The list is grouped by the kind that owns each project's largest item, so a Rails app with a small
`node_modules` sits under Rails. `CleanupGroup.groups` sorts the groups and the projects in each by
space, the most first. A group's header has a chevron, the kind's badge, its project count and
space, and a **Trash All** button for the group. A click on the header, outside the button, folds
the group, and the coordinator keeps the folded groups while the app runs. Each row keeps its own
badge too.

The header stays pinned at the top of the list while its group scrolls under it. A grouped `Form`
cannot pin a section header, so the list is a `ScrollView` with a `LazyVStack` that pins section
headers, and `CleanupGroupCard` draws each group's rounded card from `Theme.Colors.cardFill` and
`cardStroke`. The pinned header paints the window background, so rows never show through it. The badge is an SF Symbol on a tile of the kind's system
colour. No SF Symbol is a language logo, so each glyph is a nod to its ecosystem, such as a gem
for Rails. **Move All to Trash…** does the same for every project the filter lists. Both buttons have a menu with **Delete
Immediately…**, which skips the Trash.

## Build items

Most build items are folders that a project kind names, such as `node_modules`. Two other rules
exist, and `CleanupArtifactRule` names each one:

| Rule | Example | What goes |
| --- | --- | --- |
| Folder | `node_modules`, `tmp/cache` | The whole folder |
| Files | `log/*.log` | The `.log` files directly in `log`. The folder and its `.keep` stay, and so does a subfolder. |
| Virtual environment | `venv`, `parquet-venv` | Any folder that holds `pyvenv.cfg`, whatever its name |

A Rails app is a folder with `Gemfile`, `config.ru` and a `config` folder. Its build items are
`tmp/cache` and `log/*.log`. A file rule that matches no file is left out of the list.

A virtual environment belongs to the folder that holds it. If that folder is no project, it is
listed as a "Python environment". The walk does not enter the environment, so its packages are
never listed as projects.

A row says how many listed projects are inside the project, such as the packages of a monorepo.

## Invariants

- **A scan never changes a file.** `CleanupScanner` lists folders and reads their sizes and dates.
  It never writes, moves or deletes.
- **Only `CleanupRunner` removes, and only after a yes.** `CleanupCoordinator.remove` is the one
  route to the runner, and it asks through `DialogController` first. The confirmation lives in the
  coordinator, so the runner stays harness-compilable.
- **The Trash is the default.** A click moves folders to the Trash. Delete Immediately is a menu
  item, so it always takes a deliberate second step.
- **Each folder is checked again just before it goes.** `CleanupRemovalPolicy.isSafe` accepts only
  a build folder name from the table, under an absolute project path with no `..` or empty step.
  The runner then skips a folder that is gone or that a symlink replaced since the scan.
- **The harness never uses the real Trash.** `CleanupRunner.remove` takes the trash operation as a
  parameter, and `cleanup-test` passes one that moves folders inside its scratch tree.
- **A scan runs only on request.** Nothing walks the roots on a schedule or at launch. A walk of a
  large tree takes minutes.
- **The rules stay in `Model/`.** The project kinds, the walk rules, the roots, the age filter, the
  removal rules and the dialog wording import neither AppKit nor SwiftUI.
  `Tests/cleanup-test.swift` compiles them with the scanner and the runner, and runs both on a
  scratch tree.
- **A cancelled scan reports nothing.** `CleanupScanner.scan` returns nil, so a part walk never
  replaces the last full report.
- **Cleanup has its own roots.** They are not the Git Watch roots. `settings.json` holds them as
  `cleanup.roots`, abbreviated with `~`.

## Removal

1. The coordinator turns the chosen projects into one target per build folder.
2. `CleanupRemovalQuestion` words the dialog: the folder names or the folder count, the space, and
   whether the removal can be undone.
3. After a yes, `CleanupRunner` removes each folder off the main actor. A HUD shows progress.
4. The report drops each removed folder, and a project with none left drops out.
5. A HUD reports the folders and space removed. Any failure opens a dialog that names up to five
   folders and the reason for each.

Space moved to the Trash comes back only when you empty the Trash. The dialog says so.

## Origin

The marker files and their build folders come from [kondo](https://github.com/tbillington/kondo)
v0.9, by Trent Billington, under the MIT licence. [NOTICE.md](../../NOTICE.md) holds the notice.
Perch has no third-party dependencies, so `CleanupProjectKind` restates the table in Swift.

## How the walk differs from kondo

| Case | kondo | Perch |
| --- | --- | --- |
| A project inside a project | Stops at the outer project | Walks on and lists both |
| A stray marker, such as a `package.json` in a folder of projects | Hides every project under it | Lists the projects under it. The stray folder is listed only if it has a build folder, and its row says how many projects it holds. |
| A folder with two markers, such as a Rails app with `package.json` | One kind, from whichever file `readdir` returns first | Every kind, and the union of their build folders |
| A build folder that is a symlink | Follows it | Skips it |
| A hard-linked file, as in a pnpm store | Counts it as freed | Counts it as shared, not reclaimable |
| Size | Logical file length | Allocated size, which is what the disk gets back |
| Age | The newest file in the project, build folders included | The newest entry outside every build folder, without `.DS_Store` or `.git`, and the last commit from `.git/logs/HEAD` |
| Rails | Not a kind | `tmp/cache` and `log/*.log` |
| A virtual environment not named `.venv` | Each package folder is a Python project | One build item of the folder that holds it |

A build folder belongs to the first project that names it. `ios/Pods` in a React Native project is
the React Native project's, so the `Podfile` under `ios/` is not a second project.

The walk does not enter hidden folders, packages or `tmp` folders. It still reads their dates, so
a commit that changes `.git` makes the project look active. `CleanupWalkPolicy` finds a package by
its extension, because the walk reads names, not LaunchServices.

A `tmp` folder holds scratch files, not projects. One Rails app's `tmp/storage` held 137,000
folders, which was 70 percent of the walk. A Python virtual environment under `tmp` also showed up
as 267 projects, one per package folder.

## Speed

A scan has two phases, and the window shows the progress of each:

1. The walk lists each folder with `readdir` and `fstatat`, one folder at a time, because it
   decides which project owns each build folder.
2. The sizing reads each build folder with `fts`, several folders at a time in a task group.

| Change | Scan of `~/dev` |
| --- | --- |
| First version: `FileManager` for the walk and the sizing, one folder at a time | 162 s |
| `fts` sizing, up to 8 folders at a time | 73 s |
| The walk skips `tmp` | 36 s |
| `readdir` and `fstatat` for the walk | 26 s |

`fts` sized a 220,000-file `node_modules` 2.4 times faster than `FileManager`'s enumerator.
Sizing separate folders at the same time scaled to 3.7 times at 8 folders. One pnpm
`node_modules` gains nothing, because almost all of its files are in one folder, `.pnpm`.

## Limits

- APFS clones look like separate files, so a cloned folder can show more space than a delete frees.
- A running Rails server keeps writing to a log file after it is removed. The disk gets that space
  back only when the server restarts.
- A `git status` rewrites the `.git` folder without a commit, so `.git` does not date a project.
  A checkout, pull or commit updates `.git/logs/HEAD`, and that does.
