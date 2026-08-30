# CropCare AI download site

This directory is a standalone static Vercel project. It intentionally does
not contain the APK because the current release is larger than Vercel's
practical static-file limit.

## Deploy to Vercel

1. Import `cordonblue0622/CropCareAI` in Vercel.
2. Set **Root Directory** to `download_site`.
3. Select **Other** as the framework preset.
4. Leave the build and output settings empty, then deploy.
5. Add the resulting domain to Google Search Console if public search discovery
   is required.

## Publish an Android release

1. Increase `version` in the root `pubspec.yaml`. Both the semantic version and
   build number must move forward, for example `1.0.1+2` to `1.0.2+3`.
2. Build with `tool/build_release_apk.bat` using the same Android signing key.
3. In GitHub, create a release and upload the root `CropCareAI-release.apk`
   file as a release asset. Keep that exact filename.

The site reads GitHub's latest-release API and updates its version, size, and
download target automatically. Installing a newer APK with the same package ID
and signing key upgrades the existing app and preserves its data, but Android
still asks the user to approve installation.

For automatic update delivery, publish an Android App Bundle to Google Play
instead. Run `flutter build appbundle --release` with the production backend
define, upload the generated `.aab`, and retain the same Play signing identity
for every release.