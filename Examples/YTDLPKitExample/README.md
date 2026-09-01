# YTDLPKit example

This minimal SwiftUI app uses the repository checkout as a local Swift package;
it does not require YTDLPKit to be published.

1. Open `YTDLPKitExample.xcodeproj` in Xcode 16 or later.
2. Confirm the local package reference resolves to the repository root (`../../`).
3. Select an iOS 16 or later Simulator and run the app.
4. Paste a supported media URL and choose **Extract metadata**.

The example intentionally displays metadata only. It does not play, download,
or persist media, and it never displays or logs extracted format URLs.

For device testing, select your own development team in Signing & Capabilities.
Do not treat a successful build as proof that live extraction works; live source
behavior must be verified separately and is excluded from ordinary CI.
