# Bite by Bite

Personal calorie journal with separate accounts, server-saved journals, photo estimates, activity tracking, personal targets, and intake reminders. Requires Node.js 22.13+ (uses built-in SQLite; some Node releases print an experimental SQLite notice). No npm dependencies.

```sh
cp .env.example .env
npm start
```

Open http://localhost:3000 and create an account with a username and password of at least 10 characters. Restart an older running server after upgrading. Each account has its own journal, profile, and photo API connection. Signing in on another device against the same running server loads the same data. Data is loaded at sign-in/refresh; simultaneous edits in different tabs/devices use the latest saved journal, so refresh before switching devices.

## Photo estimates

For this personal app running on your Mac, open Settings → Photo estimates with ChatGPT → Continue with ChatGPT. In the OpenAI sign-in window, use your eligible Plus or Pro account and approve ChatGPT plan use. Return to Bite by Bite and select a model offered by your account that accepts images. You can also connect directly in the photo window without losing the selected photo. This option does not require an API key and uses your ChatGPT plan allowance. Plan and per-app limits apply; it is not unlimited.

Complete initial authorization on the Mac running the server (open the app through localhost or 127.0.0.1). The callback uses that Mac’s 127.0.0.1 address; connecting from a phone or a remote hosted URL is not supported by this local flow. After connection, other devices signed into the same journal account can send photo requests through the running Mac. This local-personal integration follows the [official Sign in with ChatGPT guide](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt) and its [preview requirements](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations). Publishing a hosted or commercial version may require separate OpenAI approval.

Credentials are encrypted using the same local encryption key as API connections, in a separate server-side table. Authorization uses state, nonce, PKCE, signature-verified identity tokens, and granted plan scopes. Token renewal is serialized; sign-out of the journal cancels pending authorization attempts. Disconnecting ChatGPT attempts remote refresh-token revocation, clears local tokens, and retains the issued registration so later sign-in can reuse it. If revocation cannot be confirmed, remove the app in [ChatGPT Settings → Usage](https://chatgpt.com/settings/usage). Your journal login and ChatGPT connection are separate. One ChatGPT registration is associated with each journal account.

Live ChatGPT sign-in requires your interaction and consent. Automated tests use mocked OAuth and inference responses; they do not prove your account’s eligibility or a live estimate. No existing Codex/ChatGPT credentials are read or reused.

The API-key method remains an optional alternative:

Open Settings → Photo estimates, enter your own OpenAI API key, and save. Alternatively configure `OPENAI_API_KEY` in `.env` and restart. A connected ChatGPT plan takes precedence over API keys. A failed or usage-limited ChatGPT request never falls back to an API key. If no ChatGPT plan is connected, a user’s own API key takes precedence over the server key. A configured key is not proof of available account credits; the next photo estimate reports rejected keys, rate/credit limits, or provider errors. API usage can incur charges. No key or credit is included with this project.

Keys entered in Settings are encrypted with AES-256-GCM in the database. The encryption key is in the server’s private `data/` directory; it must be retained to read saved API keys. Keys are never returned to the browser. Removing a user key falls back to the server key if one is configured.

Meal photos are resized in the browser and sent to OpenAI only after “Estimate calories” is pressed. They are not stored in the journal. Review portion assumptions and edit estimated calories before saving. The [official OpenAI image input documentation](https://developers.openai.com/api/docs/guides/images-vision) describes the underlying API.

## Profile and daily target

Settings collects age, current weight, height, goal weight, sex used by the formula, and desired weight-loss pace. “Estimate my daily target” calculates an approximate resting requirement using [Mifflin–St Jeor](https://pubmed.ncbi.nlm.nih.gov/2305711/), then uses a sedentary baseline of 1.2. The desired deficit uses a rough 7,700 kcal/kg assumption, capped at 20% of estimated maintenance. The app applies 1,200 / 1,500 kcal minimum targets for female / male formulas. These are application guardrails, not individualized safety guarantees. The rough initial timeline is not a prediction; update weight regularly as requirements change.

Automatic estimates support adults aged 18–100, exclude pregnancy/breastfeeding, and do not support underweight goal weights or weight-gain planning. Users can leave the optional profile blank and enter a clinician-agreed manual target (minimum 1,200 kcal). The [NIDDK Body Weight Planner](https://www.niddk.nih.gov/bwp) is a more detailed source for individualized planning.

The main number is net calories: food + signed adjustments − logged activity. The goal ring and intake reminders use food + signed adjustments; exercise does not increase the food allowance. This avoids treating the activity log as a reason to compensate for eating.

## Reminders

Account settings enable or disable 85% and 100% reminders. A banner appears when today’s intake reaches a threshold. Optional device notifications require an explicit permission grant, a supporting browser, and a service worker (HTTPS or localhost). Notifications are issued while the app is active and are deduplicated by account, date, and threshold during a browser tab session. This version does not include background push notifications when the app is closed. Phone/browser support varies.

## Accounts, storage, and backups

Passwords use salted scrypt hashes. Random session tokens are hashed in SQLite; the browser receives only an HttpOnly, SameSite cookie with a 30-day expiration. Logout revokes that session. Login/register attempts are rate-limited per IP. Accounts do not currently support password recovery or email verification; keep your password safe.

`data/accounts.sqlite` stores user journals, profiles, password hashes, sessions, and encrypted API keys. `data/` and `.env` are excluded from source control and are not served as web assets. Back up the whole `data/` directory while the app is stopped to preserve accounts and encryption keys; account JSON exports contain journal/profile data only. The database itself is not encrypted; protect access to the computer.

Export/import JSON from Settings. The optional “Copy my previous device journal” button appears when the old browser-local journal exists and explicitly copies it into the currently signed-in account, deduplicating entry IDs. Old entries are never automatically assigned to a user. Authenticated account data is not cached in local storage or the service worker. The offline shell can load but signing in and saving account data require the server.

## On a phone

For trusted local Wi-Fi set `HOST=0.0.0.0` in `.env`, restart, and open your computer’s LAN IP with port 3000. Your computer must stay on. Plain HTTP LAN access does not encrypt login traffic; use a private HTTPS deployment for regular phone access and installation. Set `COOKIE_SECURE=true` behind HTTPS. This version is a mobile web app, not an App Store/Play Store package. Public deployment and production account administration are not configured.

## Validation

```sh
npm test
```

Tests cover calorie arithmetic, calendar boundaries, activity calculations, target guardrails, reminder thresholds, separate account data, login/logout and persistent sessions, encrypted per-user photo keys, CSRF rejection, invalid journals, and provider request/error handling. Photo provider responses are mocked; live estimates require your API key. Browser visual QA may depend on an available browser connection.

## Nutrients, water, and supplements

Meals now store optional gram amounts for protein, fiber, sugar, total fat (including oils), and total carbohydrates. Photo estimates request all five, and each remains editable. Total carbohydrates include sugar and fiber; these fields are not extra calories to add again. Blank/unknown is different from a confirmed zero. Older meals remain valid and display unknown nutrients until edited. Daily, weekly, and monthly nutrient summaries show totals of recorded values and how many meals have a value for each nutrient. Coverage counts make partial totals visible.

The daily rituals panel follows the selected date, even when a week/month overview is selected. Water can be logged in 250/500 ml portions or a custom amount, and individual entries can be removed. A personal daily water goal is optional in Settings. The panel also shows water and supplement check-in totals for the selected week/month. This is a log, not a recommended amount of water.

Add your own supplement names, such as supplements you already take, and check each once per date. Untick to correct an entry. Archiving a supplement hides it from future checklists while retaining past check-ins; no dosage or supplement recommendations are provided. Nutrition fields and habit history are saved to the signed-in account and included in JSON backups. Importing an older backup restores its journal with empty habit history.

## Movement check-ins

Settings → Water & movement reminders controls the optional interval (15–240 minutes) and active hours in the current device’s local time. Reminders default off. Turning them on starts a timer; “I moved” and adding a new activity for today reset it. “Remind me in 15 min” snoozes it. Outside the chosen hours the banner is hidden. Reminder checks run approximately every 30 seconds while the app is open; browser timer throttling may delay them. Optional device notifications use the existing browser permission setting.

This app does not have motion-sensor access and cannot determine whether you have physically been sitting or moving. It reminds you to check in rather than asserting measured inactivity. No background push runs when the app is closed, and no exercise calories are added/deducted without an activity entry.

## iPhone app

The native tracker is in [mobile/ios/README.md](../mobile/ios/README.md). Open its Xcode project and press Command-R with your iPhone selected to update the old test build. It now includes on-device journal persistence, summaries, meal editing, nutrient details, water, supplements, profiles, reminders, and backup import/export. Photo streaming now stops at completion, supports cancellation, and has a 90-second limit. The iOS build and simulator UI were verified; updated live photo estimation still needs a physical-device check. Free Apple signing still expires after seven days.
