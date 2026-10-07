#!/usr/bin/env python3
"""Purge translations the cache no longer needs — by hand.

Usage:
    python scripts/purge_translation_orphans.py --dry-run
    python scripts/purge_translation_orphans.py

Run from the social_api/ directory with the venv active and a .env file present,
or with all required env vars exported.

The moderation sweep already runs this on every pass (sweep_service._purge),
whichever driver runs the sweep — the in-process timer or an external
scheduler — so this script needs no scheduler of its own. It exists for a one-off
clean-up: after a bulk deletion, or before a privacy audit.

It deletes translations whose content row is gone, translations of trips a
moderator removed, and translation usage counters no limit can still read. A
dry run does the same work inside a transaction and rolls it back, so the count
it prints is exact.
"""
import argparse
import sys
from pathlib import Path

# Ensure the social_api package root is on sys.path when run as a script.
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy.orm import Session

from app.services.translation_service import purge_for_sweep


def purge(db: Session, *, dry_run: bool) -> int:
    removed = purge_for_sweep(db)
    if dry_run:
        db.rollback()
    else:
        db.commit()
    return removed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="count what would go, delete nothing")
    args = parser.parse_args()

    from app.database import SessionLocal

    db = SessionLocal()
    try:
        removed = purge(db, dry_run=args.dry_run)
    finally:
        db.close()
    verb = "would be removed" if args.dry_run else "removed"
    print(f"{removed} rows {verb}.")


if __name__ == "__main__":
    main()
