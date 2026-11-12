# Native touch v12 candidate

Device acceptance pending. This changes controls only; same bundle identifier and data importer.

Verified v11 faults:
- Menu taps used MP_KeyEvent, but the pinned QC m_keydown/m_keyup callbacks are empty. Actual dispatch moved to Menu_InputEvent. v12 uses MP_InputEvent (and MR_InputEvent for reset release).
- Gameplay touch surface was hidden; no project Core Motion gyro existed.
- Hover acknowledgment could deadlock when QC selected a controller pointer instead of getmousepos.

v12 uses normalized absolute menu coordinates, engine virtual resolution and authentic QC menu handlers, without duplicate UIKit item hitboxes. Gameplay has floating left movement, relative right swipe, fire/alternate/jump and menu. Core Motion uses angular rate, landscape remapping, dt caps, stale sample rejection and mode/background resets. SDL virtual accelerometer joystick and duplicate touch mouse synthesis are disabled; real controllers remain enabled.

Host tests cover pointer sequencing, rapid taps, cancellation, reset release, ownership expiry, gyro orientation, stick deadzone and delta caps. macOS compile/package audit and physical device behavior remain separate gates.

Physical checklist: Options/Begin and empty-space taps; submenu back; hold/drag slider; both landscape orientations; left stick + look + fire simultaneously; short jump/menu taps; gyro horizontal/vertical and background/resume; preserved WRATH data.

Known limitations: no touch customization, explicit gyro toggle, or weapon wheel in this first candidate. Rag-dolls are unrelated and not included.
