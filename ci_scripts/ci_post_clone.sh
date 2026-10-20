#!/bin/sh
# Xcode Cloud: the .xcodeproj is git-ignored (XcodeGen output), so build it after cloning.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
brew install xcodegen
xcodegen generate
# Xcode Cloud won't resolve packages itself and needs Package.resolved, which lives inside the generated project.
# shortcut: resolves to the newest versions project.yml allows; commit a Package.resolved if builds must be pinned.
xcodebuild -resolvePackageDependencies -project Luminux.xcodeproj -scheme Luminux
