# macOS releases

Use the project's Developer ID signing team consistently. Keep a current login for
that team in Xcode → Settings → Accounts. Never publish an app that has not passed
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

3. Create `build/releases/1.0.0/ExportOptions.plist` with these values:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>75D25SJRM5</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
```

4. Upload through Xcode using its signed-in developer account:

```sh
xcodebuild -exportArchive -archivePath build/releases/1.0.0/Concurred.xcarchive \
  -exportOptionsPlist build/releases/1.0.0/ExportOptions.plist \
  -exportPath build/releases/1.0.0/export -allowProvisioningUpdates
```

If Apple reports an expired session, sign in again in Xcode. Do not save account
passwords or tokens in this repository. Wait for Apple's acceptance, then export
the notarized app:

```sh
xcodebuild -exportNotarizedApp -archivePath build/releases/1.0.0/Concurred.xcarchive \
  -exportPath build/releases/1.0.0/notarized
```

5. Check the exported app before packaging:

```sh
codesign --verify --deep --strict --verbose=2 build/releases/1.0.0/notarized/Concurred.app
xcrun stapler validate build/releases/1.0.0/notarized/Concurred.app
spctl --assess --type execute --verbose=2 build/releases/1.0.0/notarized/Concurred.app
lipo -archs build/releases/1.0.0/notarized/Concurred.app/Contents/MacOS/Concurred
```

6. ZIP the stapled app with `ditto -c -k --sequesterRsrc --keepParent`. Use the stable
   asset name `Concurred-macOS.zip`, then generate `SHA256SUMS.txt`. Verify a fresh
   extraction, including its signature and notarization ticket.
7. Commit and push the tested source and release notes. Create a GitHub release
   for that exact commit, attach the ZIP and checksum, then verify the README's
   download link. Increment the versioned paths above for each new release.

The README uses `/releases/latest/download/Concurred-macOS.zip`, so keep that asset
name the same across releases.

[Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
describes the Xcode workflow. The [custom workflow guide](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
covers `notarytool` when a separate Keychain credential profile is available.
