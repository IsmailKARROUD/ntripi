"""
services/account_service.py — erasing an account, the one way it is done.

Three callers, each proving who is asking in its own way, then handing over:

- DELETE /users/me — the app, after re-authenticating (password or Google).
- POST /web/delete-account — the web flow at /delete-account, for someone
  without the app: a single-use link emailed to the account's address.
- The moderation sweep — finishing the web erasures that had to wait.

erase_account does the erasure and nothing else deletes a User row. Beyond the
cascade it carries three rules, each for a reason:

- Under an open legal escalation — on the account, a trip it owns or a review
  it wrote — the WEB flow defers rather than erases (erasure_blocked): the
  account is evidence until the escalation closes, and the sweep erases it
  then. The in-app path still erases at once, keeping only the images; its
  answer is what installed builds parse, so it is unchanged.
- A suspended account's address may not open a new account afterwards. The
  block is a keyed hash (token_util.keyed_hash), kept until an operator lifts
  it at /admin/suspended.
- The web flow answers the same for every address. Its request route takes no
  database session at all; send_deletion_link runs after the response.
"""

from __future__ import annotations

import html
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, case, delete, exists, or_, select, update
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import SessionLocal, upsert_insert
from app.i18n import SUPPORTED, translator
from app.models.follow import Follow, FollowStatus
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.legal_escalation import LegalEscalation
from app.models.signup_block import SignupBlock
from app.models.user import User
from app.services import (
    admin_service, email_service, email_token_service, operator_alerts, seo,
)
from app.services.token_util import keyed_hash
from app.storage.factory import delete_from_sync

logger = logging.getLogger(__name__)

# Between the password reset's 30 minutes and verification's 24 hours: long
# enough to find the email, short enough that a forgotten link stops working.
ACCOUNT_DELETE_LINK_TTL = timedelta(hours=1)

# Deferred erasures the sweep finishes per run. Each one commits on its own.
DEFERRED_ERASURE_BATCH = 50

# Swappable so tests can hand the background job a session bound to their
# SQLite fixture (the push_service / translation_service precedent).
_session_factory = SessionLocal


# ---------------------------------------------------------------------------
# The erasure
# ---------------------------------------------------------------------------

def erase_account(db: Session, user: User) -> bool:
    """Erase `user` and everything that goes with it. Commits.

    Returns False — and changes nothing — when the account is already gone.
    Call it from sync code on a worker thread (a sync route, the sweep): the
    storage deletes go through storage.factory.delete_from_sync.

    Order is load-bearing:

    1. Lock the user row. Two erasures of one account (the web link and the
       sweep, or two devices) would otherwise both decrement the counters
       below; the second waits here, then finds the row gone.
    2. Decrement denormalized follow counters on other users BEFORE the
       cascade delete removes the follow rows and we lose the information.
       Bulk UPDATEs — the one documented exception to bump_follow_counters.
    3. Anonymize ratings: SET user_id = NULL. Explicit, not left to ON DELETE
       SET NULL alone, so the intent is clear. The score and the review text
       stay (Terms §9, Privacy §10).
    4. Collect the image keys, block a suspended account's address, delete
       the row and commit. The cascade takes itineraries, stops, annotations,
       allowlist and editor rows, locks, follows, blocks, notifications, device
       tokens, saves, appeals, refresh and email tokens, password history, the
       security audit log and the owned trips' translations.
    5. Delete the images, after the commit and best-effort: their public URLs
       outlive the rows, and a storage outage must not resurrect the account.

    Token invalidation: get_current_user fetches the user from the DB on every
    request. With the row gone it raises 401; no token blacklist is needed.
    """
    # Step 1 — populate_existing: what follows reads the row as locked, not as
    # it was when the caller loaded it.
    locked = db.execute(
        select(User)
        .where(User.id == user.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).scalar_one_or_none()
    if locked is None:
        return False

    # Step 2 — fix denormalized follow counters on other users.
    # Users that this account follows (accepted): they lose a follower.
    following_ids = db.execute(
        select(Follow.following_id).where(
            Follow.follower_id == user.id,
            Follow.status == FollowStatus.accepted,
        )
    ).scalars().all()

    if following_ids:
        db.execute(
            update(User)
            .where(User.id.in_(following_ids))
            # Clamped like bump_follow_counters: a counter that had drifted must
            # not go negative. case(), not GREATEST() — SQLite has none.
            .values(followers_count=case(
                (User.followers_count > 0, User.followers_count - 1), else_=0,
            ))
        )

    # Users that follow this account (accepted): they lose someone they follow.
    follower_ids = db.execute(
        select(Follow.follower_id).where(
            Follow.following_id == user.id,
            Follow.status == FollowStatus.accepted,
        )
    ).scalars().all()

    if follower_ids:
        db.execute(
            update(User)
            .where(User.id.in_(follower_ids))
            .values(following_count=case(
                (User.following_count > 0, User.following_count - 1), else_=0,
            ))
        )

    # Step 3 — anonymize ratings before deleting the user row.
    db.execute(
        update(ItineraryRating)
        .where(ItineraryRating.user_id == user.id)
        .values(user_id=None)
    )

    # Step 4 — collected before the delete: the rows that name the keys go with it.
    image_keys = _erasable_image_keys(db, locked)
    if not locked.is_active:
        # In the same transaction: a suspended account is never erased without it.
        _block_signup(db, locked.email)
    db.delete(locked)
    db.commit()

    # Step 5 — the images.
    for key in image_keys:
        delete_from_sync(key)
    return True


def _erasable_image_keys(db: Session, user: User) -> list[str]:
    """Storage keys to erase with the account — everything but possible evidence.

    Kept: every image while the account itself is under an open legal
    escalation, and the cover of any itinerary a moderator took down or that is
    escalated in its own right. Those rows are gone after the cascade, but the
    runbook's preservation duty attaches to the content, not to the row.
    """
    if admin_service.target_has_open_escalation(db, "user", user.id):
        return []
    keys = []
    if user.avatar_url:
        keys.append(f"avatars/{user.id}.jpg")
    if user.cover_image_url:
        keys.append(f"covers/{user.id}.jpg")
    for itinerary in db.execute(
        select(Itinerary).where(
            Itinerary.user_id == user.id, Itinerary.cover_image_url.is_not(None),
        )
    ).scalars():
        taken_down = (
            itinerary.deleted_at is not None
            or itinerary.hidden_at is not None
            or itinerary.moderation_status in ("hidden", "rejected")
        )
        if taken_down or admin_service.target_has_open_escalation(
            db, "itinerary", itinerary.id
        ):
            continue
        keys.append(f"itineraries/{itinerary.id}.jpg")
    return keys


# ---------------------------------------------------------------------------
# Deferral under an open legal escalation
# ---------------------------------------------------------------------------

def _open_escalation_on(user_id):
    """EXISTS: an open legal escalation on the account, a trip it owns or a
    review it wrote. `user_id` is a value, or User.id to correlate.

    correlate_except, not auto-correlation: the inner EXISTS sits two levels
    below the users query, and left to itself it put `users` in its own FROM —
    true for anyone's escalated trip, which would hold every deferred deletion.
    """
    owns_trip = exists().where(
        Itinerary.id == LegalEscalation.target_id,
        Itinerary.user_id == user_id,
    ).correlate_except(Itinerary)
    wrote_review = exists().where(
        ItineraryRating.id == LegalEscalation.target_id,
        ItineraryRating.user_id == user_id,
    ).correlate_except(ItineraryRating)
    return exists().where(
        LegalEscalation.closed_at.is_(None),
        or_(
            and_(
                LegalEscalation.target_type == "user",
                LegalEscalation.target_id == user_id,
            ),
            and_(LegalEscalation.target_type == "itinerary", owns_trip),
            and_(LegalEscalation.target_type == "rating", wrote_review),
        ),
    ).correlate_except(LegalEscalation)


def erasure_blocked(db: Session, user: User) -> bool:
    """True while an open legal escalation holds the account (see the module
    docstring). The web flow defers instead of erasing."""
    return bool(db.execute(select(_open_escalation_on(user.id))).scalar())


def defer_erasure(db: Session, user: User, lang: str) -> None:
    """Record a deletion the web flow cannot do yet, commit, tell the operator.

    The first request's time stands; the language is the latest request's.
    A Core UPDATE that writes updated_at back to itself: its onupdate would
    otherwise stamp now(), and /admin/suspended reads updated_at as the time an
    account was suspended.
    """
    values: dict = {"erasure_request_lang": lang, "updated_at": User.updated_at}
    if user.erasure_requested_at is None:
        values["erasure_requested_at"] = datetime.now(timezone.utc)
    user_id, username = user.id, user.username
    db.execute(
        update(User).where(User.id == user_id).values(**values)
        .execution_options(synchronize_session=False)
    )
    db.commit()

    settings = get_settings()
    body = (
        f"A request to delete the account @{html.escape(username)} ({user_id}) "
        "came in through the web page, but the account, one of its trips or one "
        "of its reviews is under an open legal escalation. Nothing has been "
        "erased. The moderation sweep erases it once every escalation on it is "
        "closed; until then it is listed on the Legal lane."
    )
    operator_alerts.email_operator(
        settings,
        subject="Ntripi — account deletion waiting on a legal escalation",
        html=email_service.branded_email_html(
            "Account deletion waiting", body, "Open the Legal lane",
            f"{settings.share_base_url}/admin/legal",
        ),
        unset_log=f"deletion of account {user_id} deferred",
    )


def pending_erasures(db: Session) -> list[tuple[User, bool]]:
    """Every deferred deletion, oldest first, with whether an escalation still
    holds it — False means the next sweep erases it. For /admin/legal."""
    return [
        (user, bool(blocked))
        for user, blocked in db.execute(
            select(User, _open_escalation_on(User.id))
            .where(User.erasure_requested_at.is_not(None))
            .order_by(User.erasure_requested_at, User.id)
        ).all()
    ]


def erase_deferred(db: Session, settings) -> int:
    """The sweep's job: erase the deferred deletions no escalation holds any
    more, and email each address that it is done. Returns how many.

    The escalation filter is in the query, so accounts still held can never
    starve the batch of ones that are free. Each erasure commits on its own,
    and one that fails is rolled back and retried on the next run.
    """
    users = db.execute(
        select(User)
        .where(User.erasure_requested_at.is_not(None), ~_open_escalation_on(User.id))
        .order_by(User.erasure_requested_at, User.id)
        .limit(DEFERRED_ERASURE_BATCH)
    ).scalars().all()

    erased = 0
    for user in users:
        try:
            # An escalation opened since the query, or the row since erased.
            if erasure_blocked(db, user):
                continue
            address, lang = user.email, user.erasure_request_lang or "en"
            if not erase_account(db, user):
                continue
        except Exception:
            db.rollback()
            logger.exception("deferred account erasure failed")
            continue
        erased += 1
        _send_erased_email(address, lang, settings)
    return erased


def _send_erased_email(address: str, lang: str, settings) -> None:
    """The deferred deletion is done — the page that took the request said we
    would write. Best-effort: send_email swallows its own failures."""
    t = translator(lang)
    keeps = (
        seo.canonical_url(seo.article_path("your-data-and-privacy"), lang, settings)
        + "#what-deletion-keeps"
    )
    email_service.send_email(
        to=address,
        subject=t("deleted_email_subject"),
        html=email_service.branded_email_html(
            t("delete_done_heading"), t("deleted_email_body"),
            t("delete_keeps_link"), keeps, lang=lang,
        ),
    )


# ---------------------------------------------------------------------------
# The emailed link
# ---------------------------------------------------------------------------

def send_deletion_link(email: str, lang: str) -> None:
    """Email a single-use deletion link to the account at `email`, if any.

    A background task, run after the request's response is complete — so that
    response cannot vary with whether the address has an account, in content or
    in time. Suspended accounts get a link too. Opens its own session, as the
    request's is gone by then. Never raises, and never logs the address.
    """
    lang = lang if lang in SUPPORTED else "en"
    address = (email or "").strip().lower()
    db = _session_factory()
    try:
        user = db.execute(
            select(User).where(User.email == address)
        ).scalar_one_or_none()
        if user is None:
            return
        raw = email_token_service.issue(
            db, user.id, email_token_service.PURPOSE_ACCOUNT_DELETE,
            ACCOUNT_DELETE_LINK_TTL,
        )
        to = user.email
        db.commit()

        settings = get_settings()
        t = translator(lang)
        link = f"{settings.share_base_url}/delete-account/confirm?token={raw}&lang={lang}"
        email_service.send_email(
            to=to,
            subject=t("delete_email_subject"),
            html=email_service.branded_email_html(
                t("delete_heading"), t("delete_email_body"),
                t("delete_email_button"), link, lang=lang,
            ),
        )
    except Exception:
        db.rollback()
        logger.exception("account deletion link could not be issued")
    finally:
        db.close()


# ---------------------------------------------------------------------------
# The sign-up block
# ---------------------------------------------------------------------------

def signup_block_hash(email: str) -> str:
    """The keyed hash a blocked address is stored and looked up by."""
    return keyed_hash((email or "").strip().lower(), get_settings().SECRET_KEY)


def is_signup_blocked(db: Session, email: str) -> bool:
    """True when `email` belonged to a suspended account that was erased, and no
    operator has lifted the block. Checked by both sign-up paths."""
    return db.get(SignupBlock, signup_block_hash(email)) is not None


def lift_signup_block(db: Session, email: str) -> bool:
    """Remove the block on `email`; True when there was one. The caller commits."""
    result = db.execute(
        delete(SignupBlock).where(SignupBlock.email_hash == signup_block_hash(email))
    )
    return bool(result.rowcount)


def _block_signup(db: Session, email: str) -> None:
    # Upsert: the address can already be blocked (an earlier account under it).
    db.execute(
        upsert_insert(db, SignupBlock)
        .values(email_hash=signup_block_hash(email))
        .on_conflict_do_nothing(index_elements=[SignupBlock.email_hash])
    )
