#!/bin/bash
# publish.sh TAG REVISION: copies the <image>-pr:TAG images built from REVISION to their release tags
set -euo pipefail
tag=$1 revision=$2
images=(amiga-fsuae amiga-fsuae-aros amiga-fsuae-apolloos)
declare -A versions dates
for image in "${images[@]}"; do
    src="docker://$REGISTRY/$image-pr:$tag"
    label() { skopeo inspect --format "{{index .Labels \"$1\"}}" "$src"; }
    version=$(label org.opencontainers.image.version)
    date=$(label build.date)
    built=$(label org.opencontainers.image.revision)
    if [ -z "$version" ] || [ -z "$date" ] || [ "$built" != "$revision" ]; then
        echo "$src is not the tested build of $revision: version '$version', date '$date', revision '$built'" >&2
        exit 1
    fi
    versions[$image]=$version dates[$image]=$date
done
echo "| image | tags | digest |"
echo "|---|---|---|"
for image in "${images[@]}"; do
    src="docker://$REGISTRY/$image-pr:$tag"
    version=${versions[$image]} date=${dates[$image]}
    for t in "$version" "$version-$date" latest; do
        skopeo copy --preserve-digests "$src" "docker://$REGISTRY/$image:$t" >&2
    done
    digest=$(skopeo inspect --format '{{.Digest}}' "$src")
    echo "| \`$image\` | \`$version\` \`$version-$date\` \`latest\` | \`${digest:7:12}\` |"
done
