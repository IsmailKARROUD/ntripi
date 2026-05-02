#!/usr/bin/env python3
"""One-time migration: copy filesystem uploads to Cloudflare R2 and update DB records.

Usage:
    # Dry run (shows what would be uploaded, touches nothing):
    python scripts/migrate_to_r2.py --dry-run

    # Live run:
    python scripts/migrate_to_r2.py

Run from the social_api/ directory with the venv active and a .env file present,
or with all required env vars exported.

The script:
  1. Walks STORAGE_FILESYSTEM_PATH and uploads every file to R2 under the same
     relative key (e.g. itineraries/abc123.jpg → R2 key itineraries/abc123.jpg).
  2. Updates any itinerary.cover_image_url that starts with STORAGE_PUBLIC_URL_PREFIX
     to the corresponding R2 public URL.
  3. Handles errors per-file — one bad file does not abort the whole migration.

After running successfully, flip STORAGE_BACKEND=r2 in Railway and redeploy.
"""
import argparse
import sys
from pathlib import Path

# Ensure the social_api package root is on sys.path when run as a script.
sys.path.insert(0, str(Path(__file__).parent.parent))

import boto3
from botocore.exceptions import ClientError
from sqlalchemy import create_engine, text

from app.config import get_settings


def _build_r2_client(settings):
    missing = [
        k
        for k in ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET", "R2_ENDPOINT", "R2_PUBLIC_URL")
        if not getattr(settings, k)
    ]
    if missing:
        print(f"ERROR: missing R2 env vars: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    client = boto3.client(
        "s3",
        endpoint_url=settings.R2_ENDPOINT,
        aws_access_key_id=settings.R2_ACCESS_KEY_ID,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        region_name="auto",
    )
    return client


def _collect_files(base_dir: Path) -> list[tuple[str, Path]]:
    """Return [(relative_key, absolute_path), ...] for every file under base_dir."""
    files = []
    for path in sorted(base_dir.rglob("*")):
        if path.is_file():
            key = path.relative_to(base_dir).as_posix()
            files.append((key, path))
    return files


def _guess_content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    return {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".gif": "image/gif",
    }.get(suffix, "application/octet-stream")


def migrate(dry_run: bool) -> None:
    settings = get_settings()

    base_dir = Path(settings.STORAGE_FILESYSTEM_PATH)
    if not base_dir.exists():
        print(f"ERROR: STORAGE_FILESYSTEM_PATH={base_dir} does not exist.", file=sys.stderr)
        sys.exit(1)

    files = _collect_files(base_dir)
    if not files:
        print("No files found under", base_dir)
        return

    print(f"Found {len(files)} file(s) under {base_dir}")

    client = _build_r2_client(settings)
    bucket = settings.R2_BUCKET
    public_url_base = settings.R2_PUBLIC_URL.rstrip("/")  # type: ignore[union-attr]
    old_prefix = settings.STORAGE_PUBLIC_URL_PREFIX.rstrip("/")

    # ---- Upload files --------------------------------------------------------
    uploaded: list[str] = []
    failed: list[tuple[str, str]] = []

    for i, (key, path) in enumerate(files, start=1):
        label = f"[{i}/{len(files)}] {key}"
        if dry_run:
            print(f"  DRY RUN — would upload: {label}")
            uploaded.append(key)
            continue

        content_type = _guess_content_type(path)
        try:
            data = path.read_bytes()
            client.put_object(
                Bucket=bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
            )
            print(f"  Uploaded {label}")
            uploaded.append(key)
        except (ClientError, OSError) as exc:
            print(f"  FAILED  {label}: {exc}", file=sys.stderr)
            failed.append((key, str(exc)))

    print(f"\nUpload summary: {len(uploaded)} succeeded, {len(failed)} failed.")
    if failed:
        print("Failed keys:")
        for key, err in failed:
            print(f"  {key}: {err}")

    # ---- Update database cover_image_url values ------------------------------
    engine = create_engine(settings.DATABASE_URL)
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT id, cover_image_url FROM itineraries WHERE cover_image_url IS NOT NULL")
        ).fetchall()

        updates: list[tuple[str, str]] = []
        for row in rows:
            old_url: str = row[1]
            if not old_url.startswith(old_prefix + "/"):
                continue
            relative_key = old_url[len(old_prefix) + 1:]
            new_url = f"{public_url_base}/{relative_key}"
            updates.append((row[0], new_url))

        print(f"\nFound {len(updates)} DB row(s) to update.")
        if dry_run:
            for itin_id, new_url in updates:
                print(f"  DRY RUN — would update itinerary {itin_id} → {new_url}")
        else:
            for itin_id, new_url in updates:
                conn.execute(
                    text("UPDATE itineraries SET cover_image_url = :url WHERE id = :id"),
                    {"url": new_url, "id": itin_id},
                )
                print(f"  Updated itinerary {itin_id} → {new_url}")
            conn.commit()
            print("DB commit done.")

    if failed:
        print("\nWARNING: some files failed to upload — review errors above before switching STORAGE_BACKEND=r2.")
        sys.exit(2)
    else:
        if dry_run:
            print("\nDry run complete. Re-run without --dry-run to apply changes.")
        else:
            print("\nMigration complete. You can now set STORAGE_BACKEND=r2 in Railway and redeploy.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Migrate filesystem uploads to Cloudflare R2.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be uploaded/updated without making any changes.",
    )
    args = parser.parse_args()
    migrate(dry_run=args.dry_run)
