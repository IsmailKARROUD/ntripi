from abc import ABC, abstractmethod


class Storage(ABC):
    """Abstract storage backend for user-uploaded files.

    Calling code uses save() / delete() / public_url() / exists() exclusively.
    The concrete implementation (filesystem, R2, S3) is chosen at startup via
    app/storage/factory.py and never referenced directly in business logic.
    """

    @abstractmethod
    async def save(self, key: str, data: bytes, content_type: str) -> str:
        """Persist bytes under the given key. Returns the public URL."""

    @abstractmethod
    async def read(self, key: str) -> bytes | None:
        """Return the stored bytes, or None if the key does not exist.

        Only the CSAM takedown path uses this: it must hash an object before
        deleting it, because afterwards the hash is the only evidence left.
        """

    @abstractmethod
    async def delete(self, key: str) -> None:
        """Delete the file at the given key. No-op if the key does not exist."""

    @abstractmethod
    def public_url(self, key: str) -> str:
        """Return the public URL for the given key (no I/O performed)."""

    @abstractmethod
    async def exists(self, key: str) -> bool:
        """Return True if a file exists at the given key."""
