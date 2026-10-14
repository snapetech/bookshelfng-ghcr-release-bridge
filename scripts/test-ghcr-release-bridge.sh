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
[[ "$source" == "ghcr.io/snapetech/chaptarrng@$EXPECTED_DIGEST" ]]
printf '%s\t%s\n' "$target" "$source" >> "$PUBLISH_LOG"
printf '{"containerimage.descriptor":{"digest":"%s"}}\n' "$MOCK_DIGEST" > "$metadata"
MOCK_DOCKER
chmod 0700 "$work/bin/docker"

run_bridge() {
  local digest="$IMAGE_DIGEST"
  local mock_digest="$MOCK_DIGEST"
  local latest_version="${LATEST_VERSION_OVERRIDE:-${RELEASE_VERSION:-1.2.3}}"
  PATH="$work/bin:$PATH" \
    RUNNER_TEMP="$work/runner" \
    GITHUB_STEP_SUMMARY="$work/summary.md" \
    PUBLISH_LOG="$work/publish.log" \
    EXPECTED_DIGEST="$digest" \
    MOCK_DIGEST="$mock_digest" \
    LATEST_VERSION="$latest_version" \
    RELEASE_VERSION="${RELEASE_VERSION:-1.2.3}" \
    SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-snapetech-org/chaptarrng}" \
    SOURCE_SHA="${SOURCE_SHA:-0123456789abcdef0123456789abcdef01234567}" \
    IMAGE_DIGEST="$IMAGE_DIGEST" \
    bash "$root/scripts/publish-aliases.sh"
}

valid_digest="sha256:$(printf x | sha256sum | cut -d ' ' -f1)"
IMAGE_DIGEST="$valid_digest"
MOCK_DIGEST="$valid_digest"
: > "$work/publish.log"
run_bridge
printf '%s\t%s\n' \
  'ghcr.io/snapetech/bookshelfng:latest' "ghcr.io/snapetech/chaptarrng@$valid_digest" \
  'ghcr.io/snapetech/bookshelfng:hardcover' "ghcr.io/snapetech/chaptarrng@$valid_digest" \
  'ghcr.io/snapetech/bookshelfng:softcover' "ghcr.io/snapetech/chaptarrng@$valid_digest" > "$work/expected.log"
cmp "$work/expected.log" "$work/publish.log"
grep -Fq "verified at \`$valid_digest\`" "$work/summary.md"

: > "$work/publish.log"
if LATEST_VERSION_OVERRIDE=1.2.2 run_bridge >/dev/null 2>&1; then
  echo 'The bridge accepted an older ChaptarrNG release.' >&2
  exit 1
fi
[[ ! -s "$work/publish.log" ]]

: > "$work/publish.log"
MOCK_DIGEST='sha256:deadbeef'
if run_bridge >/dev/null 2>&1; then
  echo 'A mismatched destination digest was accepted.' >&2
  exit 1
fi
[[ "$(wc -l < "$work/publish.log")" -eq 1 ]]

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
  if PATH="$work/bin:$PATH" RUNNER_TEMP="$work/runner" GITHUB_STEP_SUMMARY="$work/summary.md" \
    RELEASE_VERSION="$version" IMAGE_DIGEST="$digest" SOURCE_SHA="$sha" SOURCE_REPOSITORY="$source" \
    bash "$root/scripts/publish-aliases.sh" >/dev/null 2>&1; then
    echo "Bridge accepted malformed $case_name input." >&2
    exit 1
  fi
done

echo 'BookshelfNG GHCR bridge tests passed.'
