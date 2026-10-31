# Standalone phone version: feasibility

Checked 31 October 2026. This is a feasibility assessment, not an implemented phone app.

The intended result is a private app that stores its journal on the phone, does not require an always-on laptop or paid hosting, and preserves automatic photo estimates using the user's existing ChatGPT Plus plan. Manual-only or copy/paste workflows do not satisfy that requirement.

## Current implementation

The browser interface calls a Node server for accounts, SQLite persistence, protected ChatGPT credentials, OAuth callbacks, token renewal, and photo inference. Installing its current web manifest does not move the Node server to the phone. The existing laptop implementation should remain usable while a mobile prototype is evaluated.

## Confirmed requirements

- OpenAI's documented personal/open-source sign-in uses a system browser, PKCE, state, nonce, a signature-verified ID token, and an HTTP callback listener at `127.0.0.1`. The authorization and token exchange must use the same callback URI. A mobile web page cannot supply a native listening socket.
- Supported inference can accept images when the selected account model accepts them. The mobile implementation would need native networking, protected on-device token storage, serialized refresh-token renewal, and the existing streamed Responses request contract.
- Android supports installation of a release APK outside Google Play, subject to device installation policies. The build must be signed and tested on a real phone.
- Apple's free Personal Team development provisioning profiles expire after seven days. This is not a permanent, maintenance-free personal installation path. A native iPhone build also needs Xcode; only Command Line Tools are currently configured in this workspace environment.

## Not yet established

The official OpenAI pages checked do not establish a mobile-specific callback alternative or prove that this local listener will work reliably across iOS/Android app lifecycle transitions. The laptop's successful sign-in is not evidence of phone compatibility. A native wrapper alone does not solve the backend or authorization problem.

No native package, successful mobile Plus sign-in, or phone-only live photo estimate has been built or verified. Do not advertise this as ready to install.

## Next implementation gate

Choose the first target phone (iPhone, Android, or both). Before porting the whole tracker, build the smallest native prototype that can complete OpenAI's supported sign-in, store credentials securely, survive leaving and returning to the browser, refresh access, and return one photo estimate. If that fails, report the actual limitation before changing the product workflow or recommending a paid service.

Once that gate passes, port persistence to an on-device database, retain unknown-versus-zero nutrients, and migrate journals using the existing JSON export format. Keep credentials out of journal exports and do not run a copied laptop refresh session concurrently. Validate offline manual logging, photo permissions, supplement/date history, and local movement notifications separately from AI inference.

## Sources

- [OpenAI registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [OpenAI preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Android alternative distribution](https://developer.android.com/distribute/marketing-tools/alternative-distribution)
- [Apple developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)

## iPhone selected

An experimental native source project now exists in `ios/BiteByBite.xcodeproj`. It implements the connection gate only; see `ios/README.md` for installation, validation, and limitations. Native auth-core checks run successfully on the Mac, and transport/auth networking sources type-check against the macOS frameworks. The iPhone target remains unbuilt because full Xcode and the iOS SDK are not installed. No live mobile sign-in or estimate has been verified.

## Native tracker update

The initial source prototype has now been extended into a phone-local tracker. See `ios/README.md` for current features, stream/deadline fixes, and validation. Xcode/iOS SDK are now installed; the native app builds and launches in the simulator. The user has reached Plus sign-in/model access on their physical iPhone, but the updated live photo estimation and native notification delivery still require a device check. The earlier prototype-only descriptions above are historical.
