---
name: release-tendontally
description: Prepare, publish, and verify a new TendonTally macOS GitHub release. Use when asked to release, publish, tag, or ship a new TendonTally version.
---

# Release TendonTally

1. Fetch `origin`; require a clean `main`. Review commits since the latest `vX.Y.Z` tag and choose semver (fix-only: patch; user-facing feature: minor; breaking: major).
2. In `TendonTally/TendonTally.xcodeproj/project.pbxproj`, update every `MARKETING_VERSION` to the new version and increment every `CURRENT_PROJECT_VERSION` by one. The tag must equal `v$MARKETING_VERSION`.
3. Validate before publishing:
   - `git diff --check`
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TendonTally/TendonTally.xcodeproj -scheme TendonTally -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/xcode-derived CODE_SIGNING_ALLOWED=NO build`
   - If sandbox/cache errors occur, use workspace-local Swift module caches and run outside the sandbox. Do not treat those environment errors as test failures.
4. Commit `Release vX.Y.Z`, push `main`, create annotated tag `vX.Y.Z`, then push the tag. Never move or recreate a published tag.
5. The tag triggers `.github/workflows/release.yml`. Monitor with `gh run list` and `gh run watch <id> --exit-status`; inspect failures with `gh run view <id> --log-failed`.
6. Do not declare success until `gh release view vX.Y.Z --json url,isDraft,isPrerelease,assets` shows a public stable release containing `TendonTally.dmg`, `TendonTally-vX.Y.Z.dmg`, and `SHA256SUMS.txt`, and `main` is clean/synced.

If Apple returns agreement HTTP 403, ask the Account Holder to accept pending Apple Developer/App Store Connect agreements, allow propagation, and rerun the failed workflow with `gh run rerun <id> --failed`; do not create another tag.
