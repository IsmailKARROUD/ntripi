#!/usr/bin/env python3
"""Copy profile photos still linked from outside our storage — once, by hand.

Usage:
    python scripts/copy_google_avatars.py --dry-run
    python scripts/copy_google_avatars.py

Run from the social_api/ directory with the venv active and a .env file present,
or with all required env vars exported — on Railway, in the API container, right
after the deploy that copies a new Google sign-up's photo
(app/services/google_avatar.py).

Until 2026-11-09 a Google sign-up stored Google's photo URL as its avatar: never
scanned, never stripped of its metadata, served from outside the CDN that
Cloudflare's CSAM scan covers. Every avatar_url that is not one of our storage
URLs is handled here: a Google photo is copied in exactly as a new sign-up's is
(the same fetch, the same scan, the account's own avatar key) and the account
points at the copy; a photo that is refused, unreachable or not Google's leaves
the account without a photo, as a new sign-up would be left.

A dry run lists each account it would change, by id, with the photo's host —
never the address, which names the person's Google photo — and fetches nothing.
Review that list before running it for real. Each account is committed on its
own, so an interrupted run keeps what it did and a second run picks up the rest.
"""
import argparse
import asyncio
import sys
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit

# Ensure the social_api package root is on sys.path when run as a script.
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models.user import User
from app.services.google_avatar import copy_photo


def _ours(url: str) -> bool:
    """One of our storage URLs — the rule PATCH /users/me holds an avatar to
    (validators/image_url.py)."""
    settings = get_settings()
    prefixes = [settings.STORAGE_PUBLIC_URL_PREFIX]
    if settings.R2_PUBLIC_URL:
        prefixes.append(settings.R2_PUBLIC_URL)
    return any(url.startswith(prefix) for prefix in prefixes)


def copy_all(db: Session, *, dry_run: bool,
             report: Callable[[str], None] = print) -> tuple[int, int]:
    """Copies or clears every avatar linked from elsewhere; returns
    (copied, cleared) — in a dry run, (accounts found, 0)."""
    users = db.execute(
        select(User).where(User.avatar_url.is_not(None)).order_by(User.id)
    ).scalars().all()
    copied = cleared = 0
    for user in users:
        if _ours(user.avatar_url):
            continue
        host = urlsplit(user.avatar_url).hostname or "?"
        if dry_run:
            report(f"user {user.id}: photo on {host}")
            copied += 1
            continue
        url = asyncio.run(copy_photo(db, user, user.avatar_url))
        user.avatar_url = url
        db.commit()
        if url is None:
            report(f"user {user.id}: photo on {host} not copied — removed")
            cleared += 1
        else:
            report(f"user {user.id}: photo on {host} copied")
            copied += 1
    return copied, cleared


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="list the accounts it would change, fetch and change nothing")
    args = parser.parse_args()

    from app.database import SessionLocal

    db = SessionLocal()
    try:
        copied, cleared = copy_all(db, dry_run=args.dry_run)
    finally:
        db.close()
    if args.dry_run:
        print(f"{copied} photos would be copied or removed.")
    else:
        print(f"{copied} photos copied, {cleared} removed.")


if __name__ == "__main__":
    main()
