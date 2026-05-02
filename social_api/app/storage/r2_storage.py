import asyncio
import logging
from functools import partial

import boto3
from botocore.exceptions import ClientError

from app.storage.base import Storage

logger = logging.getLogger(__name__)


class R2Storage(Storage):
    """Cloudflare R2 storage backend using the S3-compatible API.

    Credentials and endpoint are read from config, not hardcoded here.
    boto3 is synchronous; all I/O is dispatched to a thread pool via
    asyncio.to_thread() so the event loop is never blocked.

    Public files are served from R2_PUBLIC_URL (either a custom domain or
    the r2.dev subdomain) — no presigned URLs needed.
    """

    def __init__(
        self,
        bucket: str,
        endpoint_url: str,
        access_key_id: str,
        secret_access_key: str,
        public_url: str,
    ) -> None:
        self._bucket = bucket
        self._public_url = public_url.rstrip("/")
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            region_name="auto",
        )

    async def save(self, key: str, data: bytes, content_type: str) -> str:
        """Upload bytes to R2 under key. Returns the public URL on success.

        Raises on any boto3/network error — never silently swallows failures.
        """
        put = partial(
            self._client.put_object,
            Bucket=self._bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
        )
        try:
            await asyncio.to_thread(put)
        except ClientError as exc:
            logger.error("R2 upload failed for key %r: %s", key, exc)
            raise
        logger.info("R2 uploaded key=%r bucket=%r", key, self._bucket)
        return self.public_url(key)

    async def delete(self, key: str) -> None:
        """Remove an object from R2. No-op if the key does not exist."""
        delete = partial(
            self._client.delete_object,
            Bucket=self._bucket,
            Key=key,
        )
        try:
            await asyncio.to_thread(delete)
        except ClientError as exc:
            logger.error("R2 delete failed for key %r: %s", key, exc)
            raise
        logger.info("R2 deleted key=%r bucket=%r", key, self._bucket)

    def public_url(self, key: str) -> str:
        return f"{self._public_url}/{key}"

    async def exists(self, key: str) -> bool:
        head = partial(self._client.head_object, Bucket=self._bucket, Key=key)
        try:
            await asyncio.to_thread(head)
            return True
        except ClientError as exc:
            if exc.response["Error"]["Code"] in ("404", "NoSuchKey"):
                return False
            logger.error("R2 exists check failed for key %r: %s", key, exc)
            raise
