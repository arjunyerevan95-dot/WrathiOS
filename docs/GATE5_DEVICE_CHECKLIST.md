# Gate 5A physical-device checklist

Use `WrathiOSGate5-v5-unsigned.ipa` with the existing
`com.arjukstudios.wrathios.gate3` App ID. Install it over Gate 4. Do not uninstall
the app or delete its container.

1. Confirm the launcher reports the existing imported-data validation summary without selecting the original source again. Capture this screen with the readable **Launch WRATH**, **Choose WRATH Folder**, and **Remove Imported Data** controls.
2. Tap **Launch WRATH** exactly once.
3. Capture the last visible startup stage before the SDL surface replaces the launcher, or capture the bounded failure view if startup returns.
4. If reached, capture the genuine WRATH main menu or genuine WRATH loading/menu assets. A project-authored status screen is not menu evidence.
5. Observe whether menu animation continues for at least ten seconds and whether the app remains responsive.
6. Record whether authentic audio is heard. If it is silent, transcribe whether the transcript says **Audio initialization passed** or **Audio initialization failed**.
7. Tap a visible menu item once using the upstream touch-to-pointer experiment. Record whether the selection responds. Do not begin a new game or load a map.
8. Only if the menu remains stable, background the app once for three seconds and return. Record whether rendering and input resume; this is exploratory evidence, not an automatic pass.
9. On failure, select and transcribe the bounded sanitized startup transcript. Confirm it contains no private absolute path.

Do not attach imported files, package contents, the application container, or
private paths to the PR or CI artifacts.
