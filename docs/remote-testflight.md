# Remote iPhone build and TestFlight

The [iPhone build workflow](../.github/workflows/iphone-build.yml) compiles the iPhone iCloud scheme on a GitHub macOS runner for every pull request. After each push to `main`, it also archives and uploads the iPhone app to App Store Connect if the Simulator build succeeds. Pull requests do not receive the signing credentials or upload a build.

## One-time TestFlight setup

1. Confirm the App Store Connect app record uses bundle ID `com.braxtonhardman.ProjectBoard` and Apple team `92F54J4WUJ`.
2. In CloudKit Console, deploy the development schema for `iCloud.com.braxtonhardman.ProjectBoard` to Production before distributing an iCloud build. Verify the app with the production environment.
3. Create a team App Store Connect API key with build upload and cloud-managed distribution signing access. Download the `.p8` file once.
4. In this repository's GitHub Settings → Secrets and variables → Actions, add repository secrets:
   - `APP_STORE_CONNECT_KEY_ID`: the key ID.
   - `APP_STORE_CONNECT_ISSUER_ID`: the issuer ID.
   - `APP_STORE_CONNECT_PRIVATE_KEY`: the complete contents of the `.p8` file, including its BEGIN/END lines.
5. Merge the automatic upload workflow into `main`. The merge push triggers its first Simulator build and, if successful, the TestFlight upload. Every later push to `main` does the same.
6. After Apple processes the upload, choose the build for an internal tester group in App Store Connect → TestFlight. Install it from TestFlight on your iPhone.

For a one-off upload without a push to `main`, open Actions → iPhone build → Run workflow and check **Upload to TestFlight**. The manual choice defaults to off. The workflow sets a unique build number from the GitHub run number, exports a signed IPA, and uploads it with Apple's altool. Apple's processing and any required TestFlight app information follow the GitHub run.

If signing reports a cloud-managed certificate permission error, check the API key role and the team's cloud-managed distribution certificate access. If provisioning fails, verify the bundle ID, iCloud capability, container, and production CloudKit schema in the Apple Developer account.
