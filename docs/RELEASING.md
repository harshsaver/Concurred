# macOS releases

Use the project's Developer ID signing team consistently. Notarization uses a
credential profile in macOS Keychain. Never publish an app that has not passed
notarization and signature validation.

1. Update the app's marketing version and build number in the Xcode project.
2. Run the tests, then archive both Mac architectures:

```sh
xcodebuild -project Concurred.xcodeproj -scheme Concurred -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/concurred-tests test

xcodebuild -project Concurred.xcodeproj -scheme Concurred -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath /tmp/concurred-release-build \
  -archivePath build/releases/1.0.0/Concurred.xcarchive \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
```

3. Set up a credential profile once. The command prompts for the developer's
   Apple Account, team ID, and app-specific password. Do not put passwords in
   shell commands, logs, or this repository.

```sh
xcrun notarytool store-credentials concurred-release
```

4. Copy the signed app, ZIP it, and submit it to Apple:

```sh
mkdir -p build/releases/1.0.0/notarized
ditto build/releases/1.0.0/Concurred.xcarchive/Products/Applications/Concurred.app \
  build/releases/1.0.0/notarized/Concurred.app
ditto -c -k --sequesterRsrc --keepParent build/releases/1.0.0/notarized/Concurred.app \
  build/releases/1.0.0/Concurred-macOS.zip
xcrun notarytool submit build/releases/1.0.0/Concurred-macOS.zip \
  --keychain-profile concurred-release --wait
```

Wait for **Accepted**, then inspect the log using the returned submission ID and
attach Apple's ticket to the app. The ZIP itself cannot be stapled.

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile concurred-release \
  build/releases/1.0.0/notarization-log.json
xcrun stapler staple build/releases/1.0.0/notarized/Concurred.app
```

5. Check the exported app before packaging:

```sh
codesign --verify --deep --strict --verbose=2 build/releases/1.0.0/notarized/Concurred.app
xcrun stapler validate build/releases/1.0.0/notarized/Concurred.app
spctl --assess --type execute --verbose=2 build/releases/1.0.0/notarized/Concurred.app
lipo -archs build/releases/1.0.0/notarized/Concurred.app/Contents/MacOS/Concurred
```

6. Recreate the ZIP from the stapled app with `ditto -c -k --sequesterRsrc --keepParent`. Use the stable
   asset name `Concurred-macOS.zip`, then generate `SHA256SUMS.txt`. Verify a fresh
   extraction, including its signature and notarization ticket.
7. Commit and push the tested source and release notes. Create a GitHub release
   for that exact commit, attach the ZIP and checksum, then verify the README's
   download link. Increment the versioned paths above for each new release.

The README uses `/releases/latest/download/Concurred-macOS.zip`, so keep that asset
name the same across releases.

See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and the [custom workflow guide](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
for signing, `notarytool`, and ticket validation.
