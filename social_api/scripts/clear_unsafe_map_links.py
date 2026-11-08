#!/usr/bin/env python3
"""Clear stop map links that fail the Google Maps link check — once, by hand.

Usage:
    python scripts/clear_unsafe_map_links.py --dry-run
    python scripts/clear_unsafe_map_links.py

Run from the social_api/ directory with the venv active and a .env file present,
or with all required env vars exported — on Railway, in the API container, right
after the deploy that tightened the check (app/validators/map_link.py).

Until 2026-11 the check accepted any maps.google.com address, Google's redirect
page included, and any google.com path starting /maps (so /maps/../url too). A
link stored then can still send a reader somewhere else from an installed
build, which opens whatever link it is given. This clears every stored link the
check now refuses, exactly as an edit removing the link would
(stop_location.normalize): the link, the place ID read from its text, its
place_source and the place refresh stamps go. The stop keeps its name, notes
and everything else; it loses its location.

A dry run lists every link it would clear and does the same work inside a
transaction it rolls back, so the count it prints is exact. Review that list
before running it for real. Nothing here moves itineraries.updated_at, so no
open editor gets a 412.
"""
import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

# Ensure the social_api package root is on sys.path when run as a script.
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.models.stop import Stop
from app.services.stop_location import normalize
from app.validators.map_link import is_google_maps_link


def clear(db: Session, *, dry_run: bool, report: Callable[[str], None] = print) -> int:
    """Clears every stored map link the check refuses; returns how many."""
    now = datetime.now(timezone.utc)
    stops = db.execute(
        select(Stop).where(Stop.map_url.is_not(None)).order_by(Stop.id)
    ).scalars().all()
    cleared = 0
    for stop in stops:
        if is_google_maps_link(stop.map_url):
            continue
        # repr(): a refused link may carry control characters — never print
        # them raw into the operator's terminal.
        report(f"stop {stop.id} (itinerary {stop.itinerary_id}): {stop.map_url!r}")
        changes = normalize({"map_url": None, "google_place_id": None}, stop, now)
        # A Core UPDATE on stops alone: the itinerary row is never touched, so
        # its updated_at (the concurrency ETag) stays where it is.
        db.execute(
            update(Stop).where(Stop.id == stop.id).values(**changes)
            .execution_options(synchronize_session=False)
        )
        cleared += 1
    if dry_run:
        db.rollback()
    else:
        db.commit()
    return cleared


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="list and count what would be cleared, change nothing")
    args = parser.parse_args()

    from app.database import SessionLocal

    db = SessionLocal()
    try:
        cleared = clear(db, dry_run=args.dry_run)
    finally:
        db.close()
    verb = "would be cleared" if args.dry_run else "cleared"
    print(f"{cleared} map links {verb}.")


if __name__ == "__main__":
    main()
