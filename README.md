# BookshelfNG GHCR release bridge

This repository republishes the exact multi-architecture digest of the ordinary ChaptarrNG release image under the mutable legacy BookshelfNG GHCR tags. The `latest`, `main`, `master`, `hardcover`, and `softcover` tags all resolve to the same standard image. They are retained as pull identities only; no compatibility image or second ChaptarrNG build is created, and versioned or pinned tags are left untouched.

The bridge accepts only a `repository_dispatch` event from the ChaptarrNG release workflow with a strict semantic version, source commit, and one `sha256:` digest for the standard image. It refuses a release unless that exact version is the current latest stable ChaptarrNG release. A shared concurrency group prevents simultaneous updates to the moving aliases. The destination and fixed tag list are defined in the script. Every published alias is checked against the same source digest; a mismatch fails the run.

Provider mode is not encoded in a container tag. The ChaptarrNG migration path must use the BookshelfNG provider setting preserved from the installation or an explicit operator-selected runtime setting. If a legacy installation did not persist that setting, migration must request it and stop safely until it is supplied; it must not guess from a tag name.

## One-time GitHub setup

1. Keep this repository under the `snapetech` personal account so its `GITHUB_TOKEN` can be granted access to the user-owned `bookshelfng` container package.
2. In the `bookshelfng` package settings, add this repository under **Manage Actions access** with package write access. The bridge reads the public ChaptarrNG package without a separate credential.
3. Install the existing **SnapeTech Automation** GitHub App on the `snapetech` account, restricted to this repository, with repository contents write access. The ChaptarrNG organization release workflow uses a generated installation token to dispatch the release event.
4. Keep `CHAPTARRNG_MIGRATION_BRIDGE_ENABLED` unset or `false` until the migration, rollback, feature-parity, and per-channel gates pass. Turning it on enables the live legacy mutable tags.

The repository and App installation are durable configuration. GitHub App installation tokens and the workflow's `GITHUB_TOKEN` are minted for each run and expire automatically; no personal access token is stored.

## Local validation

Run `bash scripts/test-ghcr-release-bridge.sh`. The test replaces Buildx with a local mock and proves that all five fixed legacy tags receive the same standard image digest, digest mismatches fail, stale releases are rejected, and malformed inputs are rejected.

## Local security scanning

Run `./scripts/security-scan-local.sh` for local Semgrep CE and the Trivy scanners that fit this repository. The installed pre-commit hook runs Semgrep on staged source/config files only; Trivy runs on demand or in CI. This public repository also runs Semgrep CE in GitHub Actions on changes and weekly. See [security-scanning.md](docs/security-scanning.md). Use `./scripts/update-security-tools.sh` to refresh local scanner data and the Trivy database.
