# Remote iPhone build and TestFlight

The [iPhone build workflow](../.github/workflows/iphone-build.yml) compiles the iPhone iCloud scheme on a GitHub macOS runner for every pull request. This Simulator build needs no Apple credentials and cannot be installed through TestFlight.

## One-time TestFlight setup

1. In App Store Connect, confirm that the app record uses the iPhone target's bundle ID, `com.braxtonhardman.ProjectBoard`, and the Apple team `92F54J4WUJ`.
2. In CloudKit Console, deploy the development schema for `iCloud.com.braxtonhardman.ProjectBoard` to Production before distributing an iCloud build. Verify the app with the production environment.
3. In App Store Connect → Users and Access → Integrations → App Store Connect API, generate a **team API key** with permission to upload builds and use cloud-managed distribution signing. Download the `.p8` file once. Do not commit or send it in chat.
4. In this repository's GitHub Settings → Secrets and variables → Actions, add:
   - `APP_STORE_CONNECT_KEY_ID`: the key ID.
   - `APP_STORE_CONNECT_ISSUER_ID`: the API issuer ID.
   - `APP_STORE_CONNECT_PRIVATE_KEY`: the complete contents of the downloaded `.p8` file, including the BEGIN/END lines.
5. After the workflow reaches the default branch, open Actions → iPhone build → Run workflow. Select the branch containing the app version you intend to distribute and check **Upload to TestFlight**. The job compiles a Simulator build, creates a production iPhone archive, and asks Xcode to upload it to App Store Connect.
6. After Apple processes the upload, choose the build for your internal tester group in App Store Connect → TestFlight. Install it from the TestFlight app on your iPhone.

The upload choice defaults to off. Pull requests only compile the Simulator build; they never receive the API key or upload anything. Apple's processing and any required TestFlight app information happen after the GitHub run. For each subsequent upload, Xcode is configured to manage the build number.

If the signing job reports a cloud-managed certificate permission error, check the API key's role and the team's cloud-managed distribution certificate access in App Store Connect. If provisioning fails, verify the bundle ID, iCloud capability, container, and production CloudKit schema in the Apple Developer account.
