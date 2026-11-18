# CarPlay-VideoPlayer
A carplay app that plays videos

## Downloading the IPA

GitHub Actions builds the iOS app and uploads an unsigned `CarPlayVideo.ipa` on pushes to `main` or `master`, pull requests, and manual workflow runs.

To download it:

1. Open the repository's **Actions** tab and select a successful **Build IPA** run.
2. Download the **CarPlayVideo-ipa** artifact at the bottom of the run summary.
3. Extract the downloaded artifact ZIP to get `CarPlayVideo.ipa`.

The IPA is unsigned because GitHub-hosted runners do not have this app's Apple signing credentials. Sign it with a compatible sideloading tool before installing. To start a build manually, choose **Build IPA** under **Actions** and select **Run workflow**.
