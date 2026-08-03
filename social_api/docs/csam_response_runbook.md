# CSAM Response Runbook

**Audience:** whoever reads `OPERATOR_EMAIL`.
**Read this before enabling Cloudflare's CSAM Scanning Tool, not after the first digest arrives.**
Pipeline context: [`media_pipeline_spec.md`](./media_pipeline_spec.md).

---

## 1. Scope and legal basis

Three independent layers can surface child-safety signals:

| Layer | When it runs | Question it answers | False positives |
|---|---|---|---|
| **Cloudflare CSAM Scanning** | serve-time, at the edge | Does this match a known-CSAM hash list? | essentially none |
| **AWS Rekognition** | upload-time, before storage | Does this look explicit? | yes, routinely |
| **User reports** (`csam` reason) | any time | A human says so | varies |

Only the first is a hash match, and only it justifies acting on an account on the strength of one signal. Rekognition guesses; a report is an allegation.

**Detection of new, unknown CSAM is out of scope.** Services that attempt it exist and need their own legal review.

**The obligation this runbook exists to meet:** Cloudflare notifies you, blocks the URL where it can, and stops there. **It does not file with NCMEC on your behalf.** Removal, reporting, and preservation are yours. Get counsel to review §6 before going live — the stances there are engineering defaults, not legal advice.

---

## 2. What arrives, and how fast

Cloudflare emails a **daily digest** listing matched file paths, and notes any it could not block. Two consequences to internalise:

- **The object was stored and probably served.** Serve-time detection cannot prevent that; only upload-time hash matching could, and we deliberately do not run it (§6).
- **Up to ~24h can pass** between the match and your email. Your 24-hour filing clock starts when **you are notified**, not when the file was uploaded.

---

## 3. Response procedure

### Step 1 — Take it down (2 minutes)

1. Open `/admin/legal`.
2. Paste one matched path into **Cloudflare CSAM notice** → *Take down and suspend*. A full URL, a bare key, or a path with `?v=` all work. Repeat per path in the digest.
3. The confirmation banner gives you the **evidence SHA-256** — copy it, you need it in step 2.

That single action: hashes the object before deleting it, writes a preservation row, clears the image from the profile or itinerary, suspends the uploader and revokes their tokens, and opens an escalation. The uploader is not notified.

If the path is refused, it is not one this app could have written — do not force it; check the digest for a path belonging to a different origin. If it is refused because *no account owns it* (the uploader already deleted their account), there is nobody left to suspend: delete the orphaned object directly in the R2 console, and note the path and date in your own records.

### Step 2 — File the CyberTipline report (within 24h of the digest)

At <https://report.cybertip.org>. Include:

- the image SHA-256 and storage key (from step 1, also in `/admin/log`),
- the uploader's username, email, account id, registration date,
- the upload timestamp and type, and the Cloudflare notice date,
- that the content was removed and the account suspended on detection.

### Step 3 — Close the loop

Record the **CyberTipline report number** in the escalation's closure note on `/admin/legal`. The note is mandatory; it is the proof the filing happened.

**Do not delete the suspended account** — see §4.

---

## 4. Preservation duties

- `image_moderation_logs` rows with `action='rejected_csam'` are **exempt from the 90-day purge** and are never deleted. The object is gone; this row and its SHA-256 are the record.
- `moderation_log` and `legal_escalations` are append-only, with no retention job.
- **Never delete the suspended user row.** Suspension preserves the account and its evidence; `delete_my_account` destroys it.
- Never re-add `rejected_csam` to a retention query, and never run migration `7f6e757d452c`'s downgrade in production without counsel sign-off — it collapses those rows into ordinary `rejected` ones and loses what made them preservable.

---

## 5. Legal counsel

Fill this in before going live and keep it current:

```
Firm / counsel:  ____________________
Phone (24h):     ____________________
Email:           ____________________
Engagement ref:  ____________________
```

**Call before acting** if: the uploader contests the match, law enforcement contacts you directly, a report involves a minor who is also a user, or you are considering any deviation from this runbook.

---

## 6. Decision log — needs counsel sign-off

| Decision | Stance | Rationale | Signed off |
|---|---|---|---|
| Detection timing | **Serve-time only** (Cloudflare); no upload-time hash matching | PhotoDNA needs a Microsoft application and NCMEC ESP paperwork that a solo operator cannot sustain. **Accepted risk: matched content is stored and may be served before detection.** | ☐ |
| Notification latency | **Daily digest accepted** | Cloudflare's cadence; not configurable. The filing clock starts at the notice, not the upload. | ☐ |
| Uploader notification | **None** — no email, no distinct error | A notice confirms what was detected to the person who uploaded it | ☐ |
| Reporting to authorities | **Manual only** | Neither Ntripi nor Cloudflare files automatically; the requirement is that these cannot be silently closed | ☐ |
| Account suspension | **Immediate, on the operator's takedown** | A hash match does not guess; reversible via the standard unban if ever disputed | ☐ |
| Evidence retention | **Indefinite** for `rejected_csam` rows | Preservation duties; the object is deleted, so nothing else survives | ☐ |

---

## 7. Readiness checklist

- [ ] `STORAGE_BACKEND=r2` live, serving from a **proxied** `images.ntripi.app` (grey-cloud DNS = no scanning)
- [ ] Cloudflare CSAM Scanning Tool enabled, notification address = `OPERATOR_EMAIL`
- [ ] That address actually interrupts you — a daily digest is useless in an unread inbox
- [ ] §5 filled in; counsel has signed off §6
- [ ] You have opened `/admin/legal` once and seen the takedown form
- [ ] Calendar reminder for a quarterly dry run: take down a harmless test image, walk steps 1 and 3 without filing, then unban the test account from `/admin/log`
