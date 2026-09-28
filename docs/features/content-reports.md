# Content reports, thresholds and CSAM response

**Status:** shipped
**Tables:** `content_reports`, `legal_escalations`
**Config:** `REPORT_HIDE_THRESHOLDS`, `REPORT_RATE_LIMIT`, `ABUSE_CONTACT_EMAIL`, `OPERATOR_EMAIL`

## Purpose

Lets any user — signed in or not — report an itinerary, a rating or a profile.
Enough distinct reporters hides the content immediately. CSAM signals open a
separate legal lane that cannot be closed without a written note.

## Rules

### The report row

- **`content_reports` is polymorphic**: `target_type` + `target_id`, **with no FK
  on the id**. Evidence must survive a hard delete of the thing it describes.
- **Canonical reasons**: `csam, sexual_content, violence_threat, hate_speech,
  harassment, other, spam`. **Legacy wire values (`nsfw`, `violence`,
  `copyright`) are accepted and normalised** by
  `report_service.normalize_reason`, so deployed clients keep working.
- **`notes` is deliberately not text-moderated** — a 422 there would block
  someone reporting hate speech who quotes it.
- **Auth is optional.** Anonymous reports are rate-limited by
  `reporter_ip_hash`, an **HMAC** of the IP, not the IP itself.
- **`has_pending_report` idempotency is what makes reporters *distinct*** — one
  user reporting repeatedly counts once.
- Reporting your own content answers 400 `report_own_content`; exceeding the
  limit answers 429 `report_rate_limited`.

### Hide thresholds

`REPORT_HIDE_THRESHOLDS` is a comma-separated `category:count` string of
**distinct reporters** required to hide content immediately:

```
csam:1, sexual_content:1, violence_threat:1,
hate_speech:2, harassment:2, other:3, spam:4
```

- **It is parsed at startup** (`config.py` calls the property so a typo fails
  at boot): a malformed entry raises, and so does a category that is not one of
  the canonical reasons (`constants/report_reasons.py`) — `harrassment:2` used to
  parse fine and silently disable auto-hide for harassment.
- **A takedown settles every pending report on its target, and a reversal
  dismisses the rest.** `auto_hide` resolves them all (`auto_hidden`, or
  `content_hidden` for an operator), as do `hide_itinerary` and the soft deletes;
  unhide, restore and a granted appeal resolve what is left as `dismissed`.
  Closing only the report that tipped the threshold left its siblings pending,
  and ~20h later the SLA sweep re-hid content a moderator had restored. A target
  under an open legal escalation keeps its reports — they close from the Legal
  lane, with a note.
- **The count drops by one (floor 1)** when the content is already flagged or a
  classifier score corroborates the reason.
- Reporter **reputation weighting is explicitly out of scope**, with the
  insertion point pre-designated: *"When it arrives it belongs in
  `_effective_threshold`, which is the only place that decides how many reporters
  are 'enough' — nothing else needs to change."* (`report_service.py:41`)

### Legal escalations

- **CSAM signals open a `legal_escalations` row**, rendered in its own
  `/admin/legal` lane.
- `source` is one of `report`, `score`, `hash_match`.
- **The routine dismiss action refuses escalated reports**, and closing one
  **demands a written note**.
- **There is no automated reporting to authorities — deliberate.**
  `models/legal_escalation.py:13`: *"Deliberately NOT implemented here:
  automated reporting to authorities. The requirement is that this category
  cannot be silently closed, not that the app files reports on its own."*

### CSAM takedown

Detection is **Cloudflare's, at serve time**; the app's whole job is the
response. `admin_service.csam_takedown(db, admin, path)`, driven by the form on
`/admin/legal`.

- **`parse_storage_key` normalises whatever the operator pastes** (full URL, bare
  key, `/uploads/` prefix, `?v=` suffix) against the three deterministic key
  patterns, and **refuses anything it does not recognise** — guessing could
  suspend an unrelated account.
- **Order is load-bearing:**
  1. **Hash the object *before* deleting it** — afterwards the `rejected_csam`
     row and its SHA-256 are the only evidence.
  2. Clear the URL (itineraries via `set_preserving_etag`).
  3. `deactivate_account`.
  4. One operator `ban` row, so `/admin/log`'s unban still works if a match is
     ever disputed.
  5. `escalate(source='hash_match')` against the **user** — no content row
     survives to point at.
  6. **Commit** — evidence, suspension and escalation as one transaction.
  7. Delete the object, best-effort.
- **The uploader is never emailed**, and no CSAM-specific message is surfaced:
  that would tell someone whose upload matched a law-enforcement corpus exactly
  what was detected.
- `rejected_csam` rows are **exempt from the 90-day purge**
  (`moderation_service.PRESERVED_ACTION`) and must never be purged, downgraded or
  otherwise touched.

**Cloudflare's CSAM Scanning Tool has no app config** — it is a dashboard toggle
(Caching → CSAM Scanning Tool), with the notification address set to
`OPERATOR_EMAIL`. It requires `STORAGE_BACKEND=r2` served from a **proxied custom
domain**; a `pub-*.r2.dev` `R2_PUBLIC_URL` bypasses the zone and **silently
disables the whole layer** (the storage factory logs a warning). It scans
**serve-time, not upload-time**, blocks matched URLs at the edge, and emails a
**daily digest** — it does **NOT** file with NCMEC on our behalf.

Removal, the CyberTipline filing (24h from the notice) and preservation are ours:
`../../social_api/docs/csam_response_runbook.md` and
`../../social_api/docs/media_pipeline_spec.md`.

### Audit rows

**Automated audit rows (`moderation_log` with `admin_user_id IS NULL`) carry
`content_snapshot=None` and no raw text, email or display name.** Operator rows
keep their snapshot.

## Data model

`content_reports` — `target_type` CHECK ∈ `{itinerary, rating, user}`,
`target_id` indexed with no FK, `reporter_user_id` FK SET NULL,
`reason` CHECK (7 values), `notes`, `reporter_ip_hash` indexed, `created_at`
indexed, `resolved_at`, `resolution` CHECK ∈ `{pending, dismissed,
content_removed, content_hidden, user_warned, user_banned, auto_hidden}`.

`legal_escalations` — `target_type`, `target_id` indexed, `source` CHECK ∈
`{report, score, hash_match}`, `report_id` FK SET NULL, `decision_id` FK SET
NULL, `closed_at` / `closed_by` / `closure_note`.

Full columns:
[reference/data-model.md](../reference/data-model.md#content_reports).
Migrations: `acd2209b7778` created reports; `a673844f962a` made them polymorphic
with canonical reasons; `eb9d286c54fb` added `legal_escalations`;
`7f6e757d452c` added the CSAM hash-match tier.

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/reports` | **optional**, `REPORT_RATE_LIMIT` | `ReportCreate{target_type, target_id, reason, notes?}` | 201 | 400 `report_own_content`, 429 `report_rate_limited`, 404 `itinerary_not_found` |

Admin-side lanes are documented in
[admin-and-appeals.md](admin-and-appeals.md): `GET /admin/reports`,
`POST /admin/reports/{id}/action`, `POST /admin/reports/bulk`,
`GET /admin/legal`, `POST /admin/legal/takedown`,
`POST /admin/legal/{escalation_id}/close`.

## Config

| Var | Default | Notes |
|---|---|---|
| `REPORT_HIDE_THRESHOLDS` | see above | parsed at startup; a typo raises |
| `REPORT_RATE_LIMIT` | `10/hour` | blunts report griefing |
| `ABUSE_CONTACT_EMAIL` | `abuse@ntripi.app` | **must match the in-app address AND the store listing** |
| `OPERATOR_EMAIL` | unset | **unset ⇒ reports are logged and nobody is told** |

## Flutter surface

- **`report_content_sheet.dart`** (`features/reports/presentation/`) — the compose
  sheet; `ugc_actions.dart` offers Report alongside Block.
- **`reportRepositoryProvider`** → `ReportRepository`
  (`features/reports/data/report_repository.dart`).
- The flag button sits on the itinerary detail screen, and an anonymous variant
  appears on the public share page.
- **The gesture is role-disjoint**: `long_press_to_edit.dart`'s invariant is
  **can-edit vs report** — an editor gets the pencil and never the flag.
- A reader can report an individual review, which is why `RatingWithUser.id` is
  in the payload.

## Known gaps / TODOs

- **Reporter reputation weighting is unbuilt** (idea), with its insertion point
  documented.
- **`POST /reports` answers `code="itinerary_not_found"` for every unreportable
  target** (`reports.py:82`), including a `rating` or `user` target.
- `csam_response_runbook.md` **§6 is a decision table with an unticked
  "Signed off" column** — counsel review is outstanding, and §7's six readiness
  boxes are unticked. `media_pipeline_spec.md` §5 has eight unticked operator
  steps. See [backlog.md](../backlog.md).
- `test_reports.py`, `test_report_thresholds.py` and `test_csam_takedown.py` all
  run.

## Related

- [admin-and-appeals.md](admin-and-appeals.md) — the lanes, the log, the sweep
- [image-moderation.md](image-moderation.md) — `rejected_csam`, `PRESERVED_ACTION`
- [text-moderation.md](text-moderation.md) — `hide_escalate` and `escalate_if_flagged`
- [blocking.md](blocking.md) — the sibling user action
- [image-pipeline.md](image-pipeline.md) — `parse_storage_key`, R2 and the edge scan
- [visibility-and-access.md](visibility-and-access.md) — what hiding does
- [notifications.md](notifications.md) — `moderation_action`, with no actor
- `../../social_api/docs/csam_response_runbook.md` · `../../social_api/docs/media_pipeline_spec.md`

## OPEN QUESTIONS

- **Accepted risk, stated in the spec** (`media_pipeline_spec.md:23`): *"because
  detection is serve-time and the digest is daily, a matched image *will* have
  been stored and possibly served before you learn of it. Upload-time hash
  matching (PhotoDNA) is the only thing that prevents that, and it was
  consciously traded away for operational simplicity."* Recorded here because it
  is a live risk, not an unknown.
- **Detection of new, unknown CSAM is out of scope** — the runbook says services
  that attempt it "exist and need their own legal review."
