# Zoidberg as the brag front end: design

**Date:** 2026-10-14
**Owner:** Alex Mathers
**Status:** Draft for review
**Related:** `~/Developer/brag-tracker` (spec: `docs/superpowers/specs/2026-10-14-brag-tracker-design.md`)

## Goal

Make the Friday brag nudge a real macOS notification that Alex can click. Add two menu-bar actions that run the brag tool on demand.

brag-tracker stays the engine: scheduling, gathering, state and the review session. Zoidberg is only the UI on the Mac.

**Why:** the current nudge is an AppleScript dialog. When launchd starts it, the dialog can open behind other windows or on another Space, time out unseen, and get logged as "Skip". The built-in `display notification` can't run anything when clicked. Zoidberg is a menu-bar app that's already signed, with bundle id `com.malecks.zoidberg`, so it can post native notifications with action buttons.

**Success looks like:**
- On Friday at 15:00 a "Brag review" notification appears. Clicking it, or its **Review now** button, opens Ghostty straight into `brag review`.
- If Alex ignores it, the notification stays in Notification Center and still works when clicked later.
- From the menu bar, Alex can start a gather and see when it has finished, or open a review, at any time.

## Out of scope

- Logging wins by hand, and an unreviewed-count badge. Alex explicitly ruled both out.
- Moving any brag logic (gather, review, state, Notion) into Zoidberg. Zoidberg only calls the `brag` CLI.
- Zoidberg's Claude API key and cleanup pipeline. These are untouched and not used here.

## Existing pieces this builds on

- **`ZoidbergApp.swift`:**
  - `AppDelegate` already owns the status item.
  - `showContextMenu()` builds the right-click menu (Settings…, Quit).
  - The app is `LSUIElement` (no Dock icon).
- **`Helpers/Settings.swift`:**
  - `AppSettings` stores values in UserDefaults.
  - It has a `launchAtLogin` toggle that is **stored but never applied**: there's no `SMAppService` call anywhere.
- **Build:** macOS 14.0 deployment target; signed with Apple Development using Automatic signing.

## Design

### 1. URL scheme `zoidberg://`

- Register `CFBundleURLTypes` in `Info.plist` with scheme `zoidberg`.
- Handle the links in `application(_:open:)` on `AppDelegate`:

| URL | Action |
|---|---|
| `zoidberg://brag-nudge?days=N` | Post the Friday review notification ("N days captured since your last review") |
| `zoidberg://brag-review` | Open the review session (same as the Review now action) |

- Unknown hosts are ignored and logged with `os_log`.
- **Why `open zoidberg://…`:** macOS launches Zoidberg if it isn't running. So `brag nudge` doesn't depend on the app already being open.

### 2. Notifications (`Services/BragNotifier.swift`)

- **API:** `UNUserNotificationCenter`. Zoidberg is its delegate, set in `applicationDidFinishLaunching`.
- **Permission:** on the first nudge, ask for `.alert` and `.sound`. If Alex refuses, log it and fall back (see §4).
- **Category:** `BRAG_REVIEW`, with these actions:
  - **Review now** (`.foreground`)
  - **Later**
- **Notification content:**
  - Title: "Brag review"
  - Body: "N days captured since your last review"
  - Thread id: `brag`, so repeat nudges group together
- **Handling `didReceive`:**
  - **Default click or Review now:** run `brag review --in-terminal` (see §5).
  - **Later:** schedule the same notification again with `UNTimeIntervalNotificationTrigger(timeInterval: AppSettings.bragLaterSeconds)`. This replaces the brag-tracker `sleep 3600` re-nudge. A Later from a re-shown notification works the same way; there's no cap, because a notification can't steal focus.
- **Persistence:** it stays in Notification Center until clicked or cleared. For a banner that doesn't disappear on its own, Alex sets Zoidberg's notification style to **Persistent** ("Alerts" on older macOS) in System Settings. This is a one-time setup and is documented, not automated.
- **Foreground:** `willPresent` returns `[.banner, .list, .sound]`, so the notification also shows while Zoidberg is active.

### 3. Menu-bar actions

The right-click menu becomes:

```
Brag: Update now          (runs `brag gather`; title "Brag: Updating…" and disabled while running)
Brag: Review…             (runs `brag review --in-terminal`)
──────────
Settings...
──────────
Quit Zoidberg
```

**Update now:**
- Runs `brag gather` as a `Process` off the main thread, with stdout and stderr captured. A gather takes about 3–5 minutes and calls headless Claude.
- On finish, it posts a result notification in category `BRAG_RESULT`:
  - **Success:** title "Brag notes updated", and the CLI's `wrote …/2026-W42.md` line (with any warning count) as the body. Clicking it opens the week note in Obsidian through `obsidian://open?path=<urlencoded path>`.
  - **Failure:** title "Brag update failed", with the first line of stderr as the body. Clicking it opens `~/Library/Logs/brag-tracker.log` in Console.
- If another gather holds the lock, `brag gather` exits 0 and logs "skipped". The notification then says "A gather is already running".
- Only one Update can run at a time from Zoidberg; the menu item is disabled while it runs.

**Review…:** behaves exactly like the notification's Review now action.

### 4. Fallbacks

- **Notifications denied:** if notification permission is denied when `zoidberg://brag-nudge` arrives, Zoidberg shows an `NSAlert` brought to the front with `NSApp.activate`, with Review now / Later / Skip. This is still better than the launchd-spawned AppleScript dialog, because Zoidberg can force itself to the front.
- **Zoidberg missing:** on the brag-tracker side, `nudge.py` uses Zoidberg only if `~/Applications/Zoidberg.app` or `/Applications/Zoidberg.app` exists. Otherwise it keeps the current dialog, with the visibility and logging fixes from §5.

### 5. Changes in brag-tracker

Make these only after the in-flight review fix pass (session developer-1e) has merged:

- **`brag nudge`:**
  - If Zoidberg is installed: `open -g "zoidberg://brag-nudge?days=N"` and log "nudge: sent to zoidberg". `-g` keeps focus where it is.
  - Otherwise: the dialog, now run through `tell application (path to frontmost application as text) to display dialog …` so it opens in front.
  - Log `gave up` and non-zero exits as `nudge: timed out` / `nudge: error <stderr>` instead of "Skip".
  - Drop `schedule_later` when Zoidberg handles Later.
- **New flag `brag review --in-terminal`:** opens the configured terminal (Ghostty) running `brag review`, using the existing `nudge.open_review`. The terminal choice stays in brag-tracker's `config.json`.
- **Config:** add `"front_end": "zoidberg"`, with values `zoidberg` or `dialog`, so the path can be forced either way.

### 6. Settings and install

- **Brag CLI path:** `AppSettings.bragPath`, default `~/.local/bin/brag`, stored in UserDefaults. No Settings UI; the default is right for Alex.
- **Later delay:** `AppSettings.bragLaterSeconds`, default 3600, stored in UserDefaults with no UI. It exists so the Later behaviour can be tested quickly.
- **Launch at login:** apply the existing toggle with `SMAppService.mainApp.register()` / `.unregister()`, so the menu actions are always there. It's already in the Settings UI; it just doesn't do anything yet.
- **Install:**
  1. Build a Release with `xcodebuild -scheme Zoidberg -configuration Release`.
  2. Copy `Zoidberg.app` to `~/Applications/`.
  3. Open it once, so LaunchServices registers the `zoidberg://` scheme.
  4. Turn on Launch at login.
- **No new entitlements.** The app isn't sandboxed, so `Process` can run `~/.local/bin/brag` directly.

## Data flow

```
launchd (Fri 15:00) → brag nudge → open -g zoidberg://brag-nudge?days=N
   → Zoidberg posts BRAG_REVIEW notification
      → click / Review now → Process: brag review --in-terminal → Ghostty: brag review
      → Later → UN trigger +1h → same notification again

Menu "Brag: Update now" → Process: brag gather → BRAG_RESULT notification → click → Obsidian note
Menu "Brag: Review…"    → Process: brag review --in-terminal
```

No work content passes through Zoidberg except the CLI's one-line result ("wrote <path>", or the first stderr line) shown in a local notification.

## Error handling

| Failure | Behaviour |
|---|---|
| `brag` not found at `bragPath` | Menu actions show a "brag CLI not found at …" notification, or an NSAlert if notifications are denied |
| Notification permission denied | Frontmost NSAlert fallback (§4) |
| `brag gather` non-zero exit | "Brag update failed" notification with the first stderr line; clicking it opens the log |
| A second Update is clicked while one runs | The menu item is disabled, so it can't happen |
| Zoidberg not running at 15:00 | `open` launches it. If launching fails, `open` exits non-zero and `brag nudge` falls back to the dialog. |

## Testing

- **Swift unit tests (`ZoidbergTests`), with a test double behind a `CommandRunner` protocol in place of the real `Process`:**
  - `BragURLRouter` parses `brag-nudge?days=3`, `brag-review` and junk links.
  - The notification content builder (title, body, category, thread id).
  - The Later action schedules a 3600 s trigger with the same content.
  - The Update result mapping: exit 0 with a "wrote" line becomes Success with an Obsidian URL; non-zero becomes Failure with the first stderr line; a "skipped" lock becomes "already running".
- **brag-tracker unit tests:**
  - `run_nudge` chooses Zoidberg when the app path exists and the dialog otherwise.
  - The dialog result parsing logs `timed out` versus `Skip`.
  - `review --in-terminal` calls `open_review`.
- **Manual checks:**
  1. `open "zoidberg://brag-nudge?days=2"`: the notification appears, and Review now opens Ghostty into `brag review`.
  2. Later: the notification reappears in about 1 h. Test with a 60 s override, `defaults write com.malecks.zoidberg bragLaterSeconds 60`.
  3. Menu Update now, then the result notification, then click to open the Obsidian note.
  4. `launchctl kickstart …brag-tracker.nudge` reaches the notification end to end from launchd.

## Open questions

None blocking. Alex sets the Persistent/Alerts notification style by hand once.
