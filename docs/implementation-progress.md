# FYP implementation record

Branch: `sprint-1/auth-screens`. Reference: all four HTML files in `mockups/`.

## Reference audit

- Auth 01–04: 24px form padding, 14px inputs, 16px buttons, 20px role cards; Syne headings and DM Sans body. Keep real registration/OTP behavior; unavailable Google/password recovery must be explicit.
- Driver 05–13: blue selection, navy navigation, 16px bordered cards, 20px major CTAs, 20px content insets. Home map, breakdown sheet, offer cards, profile sections, tracking contact card, repair cost breakdown, reviews and request history each have a reference.
- Mechanic 14–21: orange navigation selection, blue/orange actions, request cards with 14px padding, 16px cards, 40px document icons. Document reference separates CNIC, license, qualification and workshop permit. Job and earnings tabs must be reachable.
- Admin 22–27: distinct #0B1929 cards / #0F2642 borders / #060D1A sidebar, 220px sidebar, 24px content, 22px Syne titles, 14–16px card radii. Verification combines a document table, authenticated preview and reasoned review actions.
- No dedicated chat/notifications mockups: extend the reference typography, cards, icon containers and colors.
- Mockup device shells/status bars and sample metrics are presentation artifacts, not application data. Live maps and truthful lifecycle/accounting data take precedence over decorative map/ETA/sample payment content.
- IoT, fraud heuristics, SMS/email notification delivery and background push are not implemented merely because mockup samples show them.

## Current checkpoint scope

Private uploads, profile photos, explicit audited document review, and the earlier Back-navigation fix. Driver History already has a real backend-backed tab. Dialer, notifications and chat have no completed implementation in this checkpoint.

## Workspace baseline

Existing unrelated admin Cypress/dependency edits, backend startup changes and evidence artifacts were present before this task. Preserve them and stage only task changes. The prior system-Back fix belongs to this conversation and will be retained.

## Storage decision

Use authenticated MongoDB GridFS storage in the existing Atlas database. Identity evidence has no public URL. Owner/admin retrieval checks run before streaming. Avatar retrieval is authenticated. No Cloudinary account or paid storage dependency is required.

## Verification record

- Backend upload/admin/profile: 55 targeted tests passed.
- Admin API: 13 targeted tests passed, including authenticated binary previews.
- Flutter document/profile/navigation: 32 widget tests passed, including a 320px viewport and 1.6 text scale.
- TypeScript `tsc --noEmit`: passed before the final test edit; test TypeScript compiled separately.
- No physical Android device or Atlas deployment validation was performed.
