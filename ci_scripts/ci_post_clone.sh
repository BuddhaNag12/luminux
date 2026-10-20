#!/bin/sh
# Xcode Cloud: the .xcodeproj is git-ignored (XcodeGen output), so build it after cloning.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
brew install xcodegen
xcodegen generate
