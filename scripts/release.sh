#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [patch|minor|major] [--find-free] [--remote origin]

Bumps the latest vX.Y.Z tag and pushes a new annotated tag to the remote.

  bump type:   patch (default), minor, major
  --find-free  If the computed tag exists remotely, keep bumping patch until a free tag is found
  --remote     Git remote to use (default: origin)

Examples:
  $0                 # bump patch, e.g. v1.2.3 -> v1.2.4
  $0 minor           # bump minor, e.g. v1.2.3 -> v1.3.0
  $0 major --find-free
  $0 patch --remote upstream
EOF
  exit 1
}

bump_type="${1:-patch}"
find_free=0
remote="origin"

# parse extra flags
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --find-free) find_free=1 ;;
    --remote)    remote="${2:-}"; shift ;;
    -h|--help)   usage ;;
    *)           echo "Unknown arg: $1"; usage ;;
  esac
  shift || true
done

case "$bump_type" in
  patch|minor|major) ;;
  *) echo "Invalid bump type: $bump_type"; usage ;;
esac

# ensure we can reach the remote
git rev-parse --git-dir >/dev/null 2>&1 || { echo "[release] Not a git repo."; exit 1; }
git remote get-url "$remote" >/dev/null 2>&1 || { echo "[release] Remote '$remote' not found."; exit 1; }

# make sure we see everything that exists on GitHub
git fetch --tags "$remote" --quiet

latest="$(git tag --list 'v*' | sort -V | tail -n1)"

if [[ -z "$latest" ]]; then
  echo "[release] No existing tags found. Starting at v0.1.0"
  major=0 minor=1 patch=0
else
  base="${latest#v}"  # strip 'v'
  IFS=. read -r major minor patch <<<"$base"
  case "$bump_type" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
  esac
fi

candidate="v${major}.${minor}.${patch}"
echo "[release] Latest: ${latest:-<none>}  ->  Candidate: $candidate"

# ensure clean working tree
if ! git diff-index --quiet HEAD --; then
  echo "[release] ERROR: You have uncommitted changes. Commit or stash first."
  exit 1
fi

# function: does tag exist on remote?
tag_exists_remote() {
  local t="$1"
  git ls-remote --tags "$remote" "refs/tags/${t}" | grep -q .
}

if tag_exists_remote "$candidate"; then
  if [[ $find_free -eq 0 ]]; then
    echo "[release] ERROR: Tag '$candidate' already exists on remote '$remote'."
    echo "          Suggestion: run 'git fetch --tags' (already done) or choose a different bump,"
    echo "          or re-run with --find-free to auto-increment until available."
    exit 1
  else
    echo "[release] Tag '$candidate' exists. Searching for next free patch version..."
    while tag_exists_remote "$candidate"; do
      # only bump patch while searching for a free slot
      IFS=. read -r major minor patch <<<"${candidate#v}"
      patch=$((patch + 1))
      candidate="v${major}.${minor}.${patch}"
    done
    echo "[release] Using next free tag: $candidate"
  fi
fi

# create and push the tag
git tag -a "$candidate" -m "Release $candidate"
git push "$remote" "$candidate"

echo "[release] Tagged and pushed $candidate to '$remote'"
