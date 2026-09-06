# LERN design and implementation plan

Visual thesis: a private reading space, with an ink-blue full-canvas atmosphere and soft horizon light.
Content plan: the quote is the main workspace; library gives content control; reminders and profile hold secondary settings; first launch offers importing or writing your first entry.
Interaction thesis: directional crossfade on next/previous, native sheet transitions for configuration, and a restrained heart confirmation with optional haptics. Reduce Motion removes custom movement.

Tokens: night #142C46, deep ink #0B1929, daylight #EEF3F8, mist #B9C9DA, accent #A9D8F4, text #FFFFFF. Light surfaces use #EEF3F8 with #142C46 text. Display uses system rounded or serif at the user's choice; controls use SF system. No downloaded fonts.

Signature: the quote sits above a quiet horizon of light, like a thought held open. The frame remains cardless, with small source and progress cues. Theme previews may use tiles because the tile itself is the selection control.

Plan critique: generic cream/serif and green-on-black options were rejected. The default is blue atmospheric reading, not a dashboard. Color and typography remain user-editable because the brief prioritizes personalization.

Architecture: SwiftData in a background model actor, bounded pages for UI, pure import/selection/calendar engines in a local Swift package. No third-party runtime dependencies. Selection state and content sources are independent per surface. App Group storage serves iPhone and widgets; WatchConnectivity transfers a bounded Watch snapshot.

Validation sequence: Swift package tests including 50k/100k data, Xcode target build, simulator UI flows, extension builds, security audit, and GitHub Actions. Any unavailable runtime/signing validation must be reported explicitly.
