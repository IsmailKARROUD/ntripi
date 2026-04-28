from pathlib import Path

from app.storage.base import Storage


class FilesystemStorage(Storage):
    """Local filesystem storage backend. Phase 1 implementation.

    Files are stored under base_dir/{key} and served at
    {public_url_prefix}/{key} by the /uploads StaticFiles mount in main.py.
    """

    def __init__(self, base_dir: str, public_url_prefix: str) -> None:
        self._base = Path(base_dir)
        self._base.mkdir(parents=True, exist_ok=True)
        self._prefix = public_url_prefix.rstrip("/")

    async def save(self, key: str, data: bytes, content_type: str) -> str:
        path = self._base / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return self.public_url(key)

    async def delete(self, key: str) -> None:
        path = self._base / key
        if path.exists():
            path.unlink()

    def public_url(self, key: str) -> str:
        return f"{self._prefix}/{key}"

    async def exists(self, key: str) -> bool:
        return (self._base / key).exists()
