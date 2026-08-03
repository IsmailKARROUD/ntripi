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
  2. Rewrites every stored image URL — itineraries.cover_image_url,
     users.avatar_url, users.cover_image_url — from the old serving prefix to
     the R2 public URL. All three matter: the /uploads static mount only exists
     while STORAGE_BACKEND=filesystem, so any row this misses 404s the moment
     the backend flips.
  3. Handles errors per-file — one bad file does not abort the whole migration.

A later domain cutover (e.g. moving off pub-*.r2.dev onto the proxied custom
domain, which is what puts images behind Cloudflare's CSAM scanning) is the
same DB rewrite with the old domain passed as --old-base:
    python scripts/migrate_to_r2.py --dry-run --old-base https://pub-abc123.r2.dev

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


# (table, id column, url column) — every place a public image URL is persisted.
URL_COLUMNS = (
    ("itineraries", "id", "cover_image_url"),
    ("users", "id", "avatar_url"),
    ("users", "id", "cover_image_url"),
)


def rewrite_url(old_url: str, old_bases: list[str], new_base: str) -> str | None:
    """Re-point a stored URL at `new_base`, or None if it does not need it.

    Avatar and user-cover URLs carry a ?v=<ms> cache-buster appended after the
    storage key (image_service.process_and_store); it is preserved verbatim, so
    clients holding the old URL still see the same version identity.
    """
    url = (old_url or "").strip()
    if not url:
        return None
    path, sep, query = url.partition("?")
    for base in old_bases:
        if not base or not path.startswith(base + "/"):
            continue
        key = path[len(base) + 1:]
        if not key:
            return None
        return f"{new_base}/{key}{sep}{query}"
    return None


def migrate(dry_run: bool, extra_old_bases: list[str] | None = None) -> None:
    settings = get_settings()
    extra_old_bases = extra_old_bases or []

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
                # Must match R2Storage.save, or migrated objects would cache
                # differently from ones uploaded afterwards.
                CacheControl="public, max-age=3600",
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

    # ---- Update every stored image URL ---------------------------------------
    # Old bases: the filesystem prefix, plus any --old-base the operator names
    # (a pub-*.r2.dev → custom-domain cutover re-points those rows too).
    old_bases = [old_prefix] + [
        base.rstrip("/") for base in extra_old_bases
        if base.rstrip("/") and base.rstrip("/") != public_url_base
    ]

    engine = create_engine(settings.DATABASE_URL)
    with engine.connect() as conn:
        total = 0
        for table, id_col, url_col in URL_COLUMNS:
            rows = conn.execute(text(
                f"SELECT {id_col}, {url_col} FROM {table} WHERE {url_col} IS NOT NULL"
            )).fetchall()

            updates: list[tuple[str, str]] = []
            for row_id, old_url in rows:
                new_url = rewrite_url(old_url, old_bases, public_url_base)
                if new_url is not None:
                    updates.append((row_id, new_url))

            total += len(updates)
            print(f"\n{table}.{url_col}: {len(updates)} row(s) to update.")
            for row_id, new_url in updates:
                if dry_run:
                    print(f"  DRY RUN — would update {table} {row_id} → {new_url}")
                    continue
                conn.execute(
                    text(f"UPDATE {table} SET {url_col} = :url WHERE {id_col} = :id"),
                    {"url": new_url, "id": row_id},
                )
                print(f"  Updated {table} {row_id} → {new_url}")

        if not dry_run:
            conn.commit()
            print(f"\nDB commit done ({total} row(s)).")

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
    parser.add_argument(
        "--old-base",
        action="append",
        default=[],
        metavar="URL",
        help="Additional URL base to re-point at R2_PUBLIC_URL (repeatable), "
             "e.g. --old-base https://pub-abc123.r2.dev when moving off the "
             "r2.dev domain onto the proxied custom domain.",
    )
    args = parser.parse_args()
    migrate(dry_run=args.dry_run, extra_old_bases=args.old_base)
