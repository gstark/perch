import Foundation

/// The POSIX script every machine runs, so this Mac and a remote host share one code path.
enum GitWatchScript {
    static let skippedFolders = [
        "node_modules", ".build", "vendor", "Library", "DerivedData", "Pods", ".cache"
    ]

    static func make(roots: [String]) -> String {
        let skip = skippedFolders.map { "-name \(quoted($0))" }.joined(separator: " -o ")
        let scans = roots.map { "scan_root \(quoted($0))\n" }.joined()
        return body.replacingOccurrences(of: "@SKIP@", with: skip) + scans + "exit 0\n"
    }

    /// Pushes one branch with all output on stderr, so the exit status alone says if it worked.
    static func push(path: String, branch: String) -> String {
        "repo=\(quoted(path))\nbranch=\(quoted(branch))\n" + pushBody
    }

    /// Single quotes pass every byte literally; an embedded quote closes, escapes and reopens them.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static let pushBody = #"""
        export GIT_TERMINAL_PROMPT=0
        upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "$branch@{upstream}" 2>/dev/null)
        if [ -n "$upstream" ]; then
          exec git -C "$repo" push "${upstream%%/*}" "$branch:${upstream#*/}" </dev/null 1>&2
        fi
        remote=$(git -C "$repo" remote | grep -x origin || git -C "$repo" remote | head -n 1)
        if [ -z "$remote" ]; then echo "fatal: the repository has no remote" >&2; exit 1; fi
        exec git -C "$repo" push --set-upstream "$remote" "$branch" </dev/null 1>&2

        """#

    private static let body = #"""
        export GIT_OPTIONAL_LOCKS=0
        report() { printf 'repo\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
        check_repo() {
          repo=$1
          if ! git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
            report "$repo" "" clean 0; return
          fi
          branch=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
          branch=${branch#origin/}
          if [ -z "$branch" ]; then
            for candidate in main master; do
              if git -C "$repo" show-ref --verify --quiet "refs/heads/$candidate"; then
                branch=$candidate; break
              fi
            done
          fi
          if [ -z "$branch" ]; then
            branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
          fi
          if [ -z "$branch" ]; then report "$repo" "" error 0; return; fi
          if ! git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
            report "$repo" "$branch" clean 0; return
          fi
          remotes=$(git -C "$repo" remote)
          if [ -z "$remotes" ]; then
            report "$repo" "$branch" noRemote "$(git -C "$repo" rev-list --count "$branch")"; return
          fi
          upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "$branch@{upstream}" 2>/dev/null)
          if [ -z "$upstream" ]; then
            for remote in $remotes; do
              if git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
                upstream=$remote/$branch; break
              fi
            done
          fi
          if [ -z "$upstream" ]; then
            report "$repo" "$branch" unpushed "$(git -C "$repo" rev-list --count "$branch")"; return
          fi
          if ! ahead=$(git -C "$repo" rev-list --count "$upstream..$branch" 2>/dev/null); then
            report "$repo" "$branch" error 0; return
          fi
          if [ "$ahead" -gt 0 ]; then
            report "$repo" "$branch" ahead "$ahead"
          else
            report "$repo" "$branch" clean 0
          fi
        }
        scan_root() {
          root=$1
          case $root in "~") root=$HOME ;; "~/"*) root=$HOME/${root#"~/"} ;; esac
          if [ ! -d "$root" ]; then printf 'missingRoot\t%s\n' "$root"; return; fi
          find "$root" \( @SKIP@ \) -prune -o -name .git -prune -type d -print 2>/dev/null |
            while IFS= read -r gitdir; do check_repo "${gitdir%/.git}"; done
        }

        """#
}
