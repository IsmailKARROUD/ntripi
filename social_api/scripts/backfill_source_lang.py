#!/usr/bin/env python3
"""One-off: fill source_lang on rows written before language detection existed.

Usage:
    # Dry run (detects and counts, writes nothing):
    python scripts/backfill_source_lang.py --dry-run

    # Live run:
    python scripts/backfill_source_lang.py [--batch-size 500]

Run from the social_api/ directory with the venv active and a .env file present,
or with all required env vars exported.

The script:
  1. Walks each translatable table in id order (keyset paging, so a run always
     ends even though rows that stay undetectable keep source_lang NULL).
  2. Detects with the same function the write path uses, over the same fields.
  3. Writes with a Core UPDATE that sets updated_at to itself, so the column's
     onupdate never fires: itineraries.updated_at IS the If-Match ETag (moving
     it would 412 every open editor), and a review's updated_at is the date the
     ratings page shows and sorts by.

Safe to re-run: only rows whose source_lang is still NULL are read.
"""
import argparse
import sys
from pathlib import Path

# Ensure the social_api package root is on sys.path when run as a script.
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.services.translation_service import REGISTRY, detect_source_lang


def backfill(db: Session, *, dry_run: bool, batch_size: int = 500,
             out=print) -> dict[str, int]:
    """Detect and store source_lang wherever it is NULL. Returns, per content
    type, how many rows got a language (or would have, on a dry run)."""
    detected_by_type: dict[str, int] = {}
    for spec in REGISTRY:
        model = spec.model
        text_columns = [getattr(model, name) for name in spec.fields]
        # stops and transport_legs have no updated_at to protect.
        keeps_updated_at = hasattr(model, "updated_at")
        scanned = detected = 0
        last_id = None

        while True:
            query = (
                select(model.id, *text_columns)
                .where(model.source_lang.is_(None))
                .order_by(model.id)
                .limit(batch_size)
            )
            if last_id is not None:
                query = query.where(model.id > last_id)
            rows = db.execute(query).all()
            if not rows:
                break

            for row in rows:
                scanned += 1
                lang = detect_source_lang(row[1:])
                if lang is None:
                    continue
                detected += 1
                if dry_run:
                    continue
                values = {"source_lang": lang}
                if keeps_updated_at:
                    values["updated_at"] = model.updated_at
                db.execute(
                    update(model)
                    .where(model.id == row.id)
                    .values(**values)
                    .execution_options(synchronize_session=False)
                )
            last_id = rows[-1].id
            if not dry_run:
                db.commit()  # per batch: a long run keeps what it has done

        detected_by_type[spec.content_type] = detected
        out(f"{spec.content_type}: {scanned} scanned, {detected} detected")
    return detected_by_type


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="detect and count, write nothing")
    parser.add_argument("--batch-size", type=int, default=500)
    args = parser.parse_args()

    from app.database import SessionLocal

    db = SessionLocal()
    try:
        backfill(db, dry_run=args.dry_run, batch_size=args.batch_size)
    finally:
        db.close()
    if args.dry_run:
        print("\nDry run complete. Re-run without --dry-run to apply changes.")


if __name__ == "__main__":
    main()
