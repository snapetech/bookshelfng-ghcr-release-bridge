#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${SOURCE_REPOSITORY:?SOURCE_REPOSITORY is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

[[ "$SOURCE_REPOSITORY" == 'snapetech-org/chaptarrng' ]]
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$IMAGE_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]
[[ "$SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]]

latest_tag="$(gh release view --repo "$SOURCE_REPOSITORY" latest --json tagName --jq .tagName)"
if [[ "$latest_tag" != "v${RELEASE_VERSION}" ]]; then
  echo "Refusing ChaptarrNG ${RELEASE_VERSION}; the current latest release is ${latest_tag}." >&2
  exit 1
fi

source_image="ghcr.io/snapetech/chaptarrng@$IMAGE_DIGEST"
summary="$GITHUB_STEP_SUMMARY"
printf "## BookshelfNG GHCR aliases\n\nSource: \`%s\` from ChaptarrNG \`%s\` (%s).\n\n" \
  "$source_image" "$RELEASE_VERSION" "$SOURCE_SHA" >> "$summary"

index=0
for alias in latest hardcover softcover; do
  target="ghcr.io/snapetech/bookshelfng:$alias"
  metadata="$RUNNER_TEMP/bookshelfng-alias-$index.json"
  index=$((index + 1))
  docker buildx imagetools create --tag "$target" --metadata-file "$metadata" "$source_image"
  actual_digest="$(python3 - "$metadata" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    value = json.load(stream)
print(value.get('containerimage.descriptor', {}).get('digest', ''))
PY
)"
  if [[ "$actual_digest" != "$IMAGE_DIGEST" ]]; then
    echo "Digest check failed for $target." >&2
    printf -- "- \`%s\`: digest check failed.\n" "$target" >> "$summary"
    exit 1
  fi
  printf -- "- \`%s\`: verified at \`%s\`.\n" "$target" "$IMAGE_DIGEST" >> "$summary"
done
