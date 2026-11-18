# CarPlay-VideoPlayer
A carplay app that plays videos

## Downloading the IPA

GitHub Actions builds the iOS app and uploads an unsigned `CarPlayVideo.ipa` on pushes to `main` or `master`, pull requests, and manual workflow runs.

To download it:

1. Open the repository's **Actions** tab and select a successful **Build IPA** run.
2. Download the **CarPlayVideo-ipa** artifact at the bottom of the run summary.
3. Extract the downloaded artifact ZIP to get `CarPlayVideo.ipa`.

The IPA is unsigned because GitHub-hosted runners do not have this app's Apple signing credentials. Sign it with a compatible sideloading tool before installing. To start a build manually, choose **Build IPA** under **Actions** and select **Run workflow**.

## CarPlay video support

The CarPlay interface uses Apple's native video-app templates so iOS and the vehicle can adapt it to supported CarPlay displays. Apple must approve the `com.apple.developer.carplay-video` entitlement and a matching provisioning profile before iOS will list the app in CarPlay; [request the entitlement from Apple](https://developer.apple.com/contact/carplay). The unsigned Actions IPA does not grant that entitlement. CarPlay video availability and driving restrictions are controlled by iOS and the vehicle; third-party apps can't capture or take over playback from the YouTube app. To play a YouTube video in this app, open its link here first. YouTube links are not offered in the CarPlay library because the embedded player isn't a native CarPlay video source.
