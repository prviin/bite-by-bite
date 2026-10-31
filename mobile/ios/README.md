# Bite by Bite for iPhone

The native app now includes the daily journal, day/week/month summaries and daily rhythm, editable food/activity/calorie adjustments, protein/fiber/sugar/fat/carbohydrate tracking, water, supplement checklists, personal calorie targets, reminders, camera/library photos, and JSON import/export. The journal is stored on the iPhone, independently of the laptop. ChatGPT credentials remain in Keychain.

## Update the installed app

1. Open `mobile/ios/BiteByBite.xcodeproj` in Xcode.
2. Keep the existing bundle identifier and Personal Team so the installed app can be updated in place.
3. Connect and unlock your iPhone and select it as the destination.
4. Press **Command-R**. The old connection-test screen is replaced with the tracker home screen.
5. Use Meal photo → choose/take a photo → optionally describe what you ate → Estimate calories & nutrients → review fields → Save.

The photo details box accepts context such as “I ate half the cake” or “only the rice, no sauce.” The estimate requests calories and all nutrients for the consumed portion, with assumptions in its notes. Leaving it empty estimates the whole pictured serving. Details are saved with the meal and included in backups. After changing details, estimate again before saving; do not halve the returned values a second time.

Do not delete the app to update it. Deleting it can remove its journal. Existing Keychain credentials are reused; the new journal starts empty until you log meals or import a backup.

Free Apple Personal Team signing expires after seven days. Re-sign/reinstall from the Mac to renew it. No hosted server is needed for ordinary phone use, but internet is required for photo estimation.

## Photo estimation fixes

The previous implementation waited for the streamed HTTP connection to close after `response.completed`. The new `EstimateStreamParser` stops immediately at that completed event and can read the final response's output even if no text deltas arrived. Failed/incomplete streams do not create journal entries.

The photo screen shows its own progress, elapsed time, status, and Cancel button. An overall 90-second deadline covers preparation/network access and resets the UI if the estimate stalls. The dedicated photo URLSession also has resource/request limits. Cancel preserves the selected photo. Generation checks prevent an older cancelled request from overwriting a newer result. Rotating token refreshes are serialized, with identity checks before replacing credentials. No paid API-key fallback is used.

A live OpenAI request can still fail due to plan limits, model support, authentication, or connectivity. Errors are shown beside the photo. The code/build/tests here do not establish that the physical phone's live request succeeds; that must be checked after updating.

## Journal and data

- Food entries have optional nutrients in grams. Unknown stays unknown, and summaries show per-nutrient coverage counts. Sugar/fiber are already included in carbohydrates; fat includes oils.
- Net calories = food + signed adjustments − activity. Food-target progress and reminders do not subtract exercise.
- Tap journal entries to edit; swipe to delete. Activity estimates use duration, weight, and an intensity preset, and can be overridden.
- Water and supplements are logged by the selected date. Archive supplements without removing previous check-ins.
- Optional personal profiles use the same conservative adult target calculation as the web version. Targets and timelines remain estimates.
- The journal is written atomically to Application Support with complete file protection on iOS. An unreadable existing journal is preserved rather than overwritten with defaults.
- Journal backup imports validate the data and retain a copy of the previous phone file before replacing it. Exports contain no ChatGPT tokens.
- To bring over the laptop journal, export JSON in its Settings, send the file to the phone (e.g. AirDrop/Files), and use **iPhone Settings → Import laptop or phone backup**. There is no automatic laptop/phone synchronization or server account system in this personal phone-local edition.

## Reminders

Enable notification permission in Settings. Intake reminders appear at 85%/100% and are deduplicated per day. Movement notifications schedule up to 50 check-ins during the next 24 hours, within the active window, when you use the app. Tap I moved or log today's activity to reset the timer. They can be delivered after the app closes, but opening the app daily is needed to replenish the next day's schedule. The app does not measure physical inactivity and does not automatically subtract activity calories.

## Verification

- iOS Simulator SDK build completed successfully.
- The tracker launched in an isolated iPhone simulator; light/dark screenshots were inspected.
- Native core regression checks cover PKCE, callback validation, signature-verified identity/claims, unknown nutrients, completed/failing/truncated streams, durable journal saves/reloads, totals, water/supplements, calendar boundaries, activity calculations, and backup import/export.
- Physical iPhone Plus sign-in/model loading was reported by the user; the updated live photo estimate and native reminder delivery still need a physical-device check.

Run the native checks from the project root:

```sh
swiftc -module-cache-path /tmp/bite-swift-module-cache mobile/ios/BiteByBite/AuthCore.swift mobile/ios/BiteByBite/JournalStore.swift mobile/ios/Checks/AuthCoreChecks.swift -o /tmp/bite-auth-core-checks
/tmp/bite-auth-core-checks mobile/ios/Checks/identity-fixture.json
```

The identity fixture is fake test data signed with an ephemeral test RSA key; checks do not access Keychain or make network requests.

Sources: [OpenAI sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [OpenAI request requirements](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [Apple account limitations](https://developer.apple.com/help/account/basics/about-your-developer-account).
