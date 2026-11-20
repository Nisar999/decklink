# DeckLink

PC agent (Windows .exe) + iPhone app. One deck per open window on your PC; swipe up/down on the phone to move between decks.

## 1. Get the apps built (free, no Mac needed)
1. Create a GitHub repo and push this whole folder to it (a public repo gets free build minutes).
2. Open the repo's Actions tab. The "build" workflow runs on every push (or press Run workflow).
3. When both jobs are green, open the run and download two artifacts:
   - DeckLink-windows-exe -> DeckLink.exe
   - DeckLink-ios-ipa -> DeckLink.ipa

## 2. Windows
Double-click DeckLink.exe. SmartScreen may warn because the file is unsigned: More info -> Run anyway.
Allow it through the firewall on private networks. A window opens with two QR codes.
Your editable decks live in `C:\Users\<you>\DeckLink\layouts.json`.

## 3. iPhone (sideload from Windows)
1. Install Sideloadly (sideloadly.io) and iTunes/Apple Devices from Microsoft Store.
2. Plug in the iPhone, drag DeckLink.ipa into Sideloadly, sign in with your Apple ID, Start.
3. On the iPhone: Settings -> Privacy & Security -> Developer Mode -> On (restarts the phone).
   Then Settings -> General -> VPN & Device Management -> trust your Apple ID.
4. Free Apple IDs expire the app every 7 days: re-run Sideloadly to refresh. A paid developer account lasts a year.
5. Open the Camera app, scan the first QR code in the DeckLink window. The app opens and pairs.

## No app yet?
Scan the second QR with the Camera, open it in Safari, Share -> Add to Home Screen. Same decks, fewer features.

## Editing decks
layouts.json: each context has `match` (exe names and/or window-title words) and `buttons`.
Action types: hotkey, key, text, url, run, win (op: min, max, restore, close). Saved changes apply instantly.
