# Gate 4 physical-device acceptance checklist

Use the replacement unsigned Gate 4 IPA with the existing `com.arjukstudios.wrathios.gate3` App ID and app container. Do not attach licensed files, private paths, bookmarks, or app-container contents to acceptance evidence.

1. Launch with no imported data. Capture the **No imported data** status and both readable action-button titles.
2. Select an unrelated or invalid folder. Capture the explicit **Invalid folder rejected** status and its structural validation reason.
3. Select either a valid licensed WRATH root containing `kp1` or the licensed `kp1` folder itself.
4. Observe **Source data validation passed**. During the long copy, capture **Copy in progress** with the completed source-validation line.
5. Wait for completion. Capture **Post-copy validation passed**, including the profile, file count, package count, total size, sentinel result, and **Imported during this session** origin.
6. Force-quit the app and relaunch it.
7. Without selecting the original source again, capture **Imported data available after relaunch**, including **Detected at launch** and the same validation metadata.
8. Tap **Remove Imported Data**, confirm removal, and capture **Imported data removed**.
9. Confirm the app exposes no installed-data removal action and explicitly reports that no imported data remains.
10. Force-quit and relaunch once more. Capture **No imported data** to prove removal persisted.

For every screenshot, verify that no original absolute source path, security-scoped bookmark, app-container path, or unrelated filename is visible.
