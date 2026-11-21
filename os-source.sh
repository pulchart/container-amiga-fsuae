#!/bin/bash
# os-source.sh REPO COMMIT PRS OUT: COMMIT with PRS ("<number>:<head commit> ...") merged, source facts to OUT
set -euo pipefail
repo=$1 commit=$2 prs=$3 out=$4

git init -q .
git remote add origin "$repo"
git fetch -q --filter=blob:none origin "$commit"
git checkout -q FETCH_HEAD
for pr in $prs; do
    git fetch -q --filter=blob:none origin "pull/${pr%%:*}/head"
    case "$(git rev-parse FETCH_HEAD)" in
        "${pr#*:}"*) ;;
        *) echo "pull request ${pr%%:*} is not at ${pr#*:}" >&2; exit 1 ;;
    esac
    git -c user.name=os-build -c user.email=os-build@localhost \
        merge -q --no-edit -m "Merge pull request ${pr%%:*}" FETCH_HEAD
done
git submodule update -q --init --recursive --depth 1
mkdir -p "$(dirname "$out")"
date=$(TZ=UTC git show -s --format=%cd --date=format-local:%Y%m%d "$commit")
printf 'commit=%s\ndate=%s\nprs=%s\n' "$commit" "$date" "$prs" >"$out"
