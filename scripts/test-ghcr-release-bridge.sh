#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/bookshelfng-ghcr-bridge.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/runner"

cat > "$work/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'release view --repo snapetech-org/chaptarrng latest --json tagName --jq .tagName' ]]
printf 'v%s\n' "$LATEST_VERSION"
MOCK_GH
chmod 0700 "$work/bin/gh"

cat > "$work/bin/docker" <<'MOCK_DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == buildx && "$2" == imagetools && "$3" == create ]]
shift 3
target=""
metadata=""
source=""
while (($#)); do
  case "$1" in
    --tag) target="$2"; shift 2 ;;
    --metadata-file) metadata="$2"; shift 2 ;;
    *) source="$1"; shift ;;
  esac
done
[[ "$source" == "ghcr.io/snapetech-org/chaptarrng@$IMAGE_DIGEST" ]]
printf '%s\t%s\n' "$target" "$source" >> "$PUBLISH_LOG"
printf '{"containerimage.descriptor":{"digest":"%s"}}\n' "${MOCK_DIGEST:-$IMAGE_DIGEST}" > "$metadata"
MOCK_DOCKER
chmod 0700 "$work/bin/docker"

run_bridge() {
  local latest_version="${LATEST_VERSION_OVERRIDE:-$RELEASE_VERSION}"
  PATH="$work/bin:$PATH" \
    RELEASE_VERSION="$RELEASE_VERSION" \
    IMAGE_DIGEST="$IMAGE_DIGEST" \
    SOURCE_SHA="$SOURCE_SHA" \
    SOURCE_REPOSITORY="$SOURCE_REPOSITORY" \
    MOCK_DIGEST="$MOCK_DIGEST" \
    RUNNER_TEMP="$work/runner" \
    GITHUB_STEP_SUMMARY="$work/summary.md" \
    PUBLISH_LOG="$work/publish.log" \
    LATEST_VERSION="$latest_version" \
    bash "$root/scripts/publish-aliases.sh"
}

valid_digest="sha256:$(printf x | sha256sum | cut -d ' ' -f1)"
IMAGE_DIGEST="$valid_digest"
RELEASE_VERSION=1.2.3
SOURCE_SHA=0123456789abcdef0123456789abcdef01234567
SOURCE_REPOSITORY=snapetech-org/chaptarrng
MOCK_DIGEST=""
: > "$work/publish.log"
run_bridge

source_image="ghcr.io/snapetech-org/chaptarrng@$valid_digest"
for alias in latest main master hardcover softcover; do
  printf '%s\t%s\n' "ghcr.io/snapetech/bookshelfng:$alias" "$source_image"
done > "$work/expected.log"
cmp "$work/expected.log" "$work/publish.log"
[[ "$(cut -f2 "$work/publish.log" | sort -u | wc -l)" -eq 1 ]]
grep -Fq "single standard ChaptarrNG image \`$source_image\`" "$work/summary.md"
grep -Fq 'Provider mode is not encoded by the tag' "$work/summary.md"
[[ "$(grep -Fc 'verified at the standard digest' "$work/summary.md")" -eq 5 ]]

: > "$work/publish.log"
if LATEST_VERSION_OVERRIDE=1.2.2 run_bridge >/dev/null 2>&1; then
  echo 'The bridge accepted an older ChaptarrNG release.' >&2
  exit 1
fi
[[ ! -s "$work/publish.log" ]]

: > "$work/publish.log"
MOCK_DIGEST=sha256:deadbeef
if run_bridge >/dev/null 2>&1; then
  echo 'A mismatched destination digest was accepted.' >&2
  exit 1
fi
[[ "$(wc -l < "$work/publish.log")" -eq 1 ]]
MOCK_DIGEST=""

for case_name in invalid_version invalid_digest invalid_sha invalid_source; do
  version=1.2.3
  digest="$valid_digest"
  sha=0123456789abcdef0123456789abcdef01234567
  source=snapetech-org/chaptarrng
  case "$case_name" in
    invalid_version) version=1.2 ;;
    invalid_digest) digest=latest ;;
    invalid_sha) sha=not-a-commit ;;
    invalid_source) source=attacker/repo ;;
  esac
  : > "$work/publish.log"
  if RELEASE_VERSION="$version" IMAGE_DIGEST="$digest" SOURCE_SHA="$sha" \
    SOURCE_REPOSITORY="$source" run_bridge >/dev/null 2>&1; then
    echo "Bridge accepted malformed $case_name input." >&2
    exit 1
  fi
  [[ ! -s "$work/publish.log" ]]
done

echo 'BookshelfNG GHCR single-standard-image bridge tests passed.'
