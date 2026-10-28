"""
test_radius_scale.py — the web pages draw their corners from the app's scale.

The app names one corner radius per job (a card, a field, a button, a pill…)
in social_flutter's lib/core/ui/app_radii.dart, NtripiRadius. The web pages
mirror it as CSS variables in app/templates/_radius_tokens.html. The two
codebases share no runtime code, so this is the one test that reads across
them: a scale kept in two places drifts unless something fails when it does.

Coverage:
  TestTheScaleIsMirrored — the partial carries exactly NtripiRadius's tokens
                           and values, and every page layout includes it
  TestNoTypedRadius      — every border-radius in a template is a token, 0 or
                           50%; the phone mockup and inline code are exempt
  TestEmailButton        — the email's button, which cannot use a CSS
                           variable, still has the button radius
"""

import re
from pathlib import Path

API = Path(__file__).resolve().parents[1]
TEMPLATES = API / "app" / "templates"
PARTIAL = TEMPLATES / "_radius_tokens.html"
APP_RADII = (
    API.parent / "social_flutter" / "lib" / "core" / "ui" / "app_radii.dart"
)

# Every template that starts a document. Each includes the partial, or its
# var(--radius-*) resolve to nothing and every corner on the page goes square.
LAYOUTS = {"_base.html", "_share_layout.html", "home.html", "admin/_base.html"}

# Not chrome, so not on the scale: the homepage's phone mockup is a small
# drawing of the app at its own size, and inline code is a text style.
EXEMPT_SELECTORS = (".phone-", ".pm-", ".hc-prose code")

_TOKEN = re.compile(r"var\(--radius-([a-z-]+)\)")
# Jinja tags and comments — blanked so their braces are not read as CSS.
_NOT_CSS = re.compile(r"\{\{.*?\}\}|\{%.*?%\}|\{#.*?#\}|/\*.*?\*/|<!--.*?-->", re.S)


def _kebab(name: str) -> str:
    return re.sub(r"(?<!^)([A-Z])", r"-\1", name).lower()


def _app_scale() -> dict[str, float]:
    assert APP_RADII.exists(), (
        f"{APP_RADII} is missing — this test holds the web pages' radii to "
        "the app's, so it runs with the whole monorepo checked out"
    )
    found = re.findall(
        r"static const double (\w+) = ([\d.]+);", APP_RADII.read_text()
    )
    assert found, f"no radius found in {APP_RADII}"
    return {_kebab(name): float(value) for name, value in found}


def _web_scale() -> dict[str, float]:
    return {
        name: float(value)
        for name, value in re.findall(
            r"--radius-([a-z-]+):\s*([\d.]+)px", PARTIAL.read_text()
        )
    }


def _templates() -> dict[str, str]:
    return {
        str(path.relative_to(TEMPLATES)): path.read_text()
        for path in sorted(TEMPLATES.rglob("*.html"))
    }


def _radius_declarations(text: str):
    """(where, value, line) for every border-radius in a template — `where`
    is the CSS rule's selector, or "inline" for a style="…" attribute."""
    clean = _NOT_CSS.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), text)
    for match in re.finditer(r"border-radius\s*:\s*([^;}\"]+)", clean):
        at = match.start()
        attribute = clean.rfind('style="', 0, at)
        if attribute != -1 and '"' not in clean[attribute + len('style="') : at]:
            where = "inline"
        else:
            brace = clean.rfind("{", 0, at)
            start = max(clean.rfind(c, 0, brace) for c in "{}>")
            where = " ".join(clean[start + 1 : brace].split())
        yield where, match.group(1).strip(), clean.count("\n", 0, at) + 1


# ---------------------------------------------------------------------------
# TestTheScaleIsMirrored
# ---------------------------------------------------------------------------


class TestTheScaleIsMirrored:
    def test_the_partial_carries_the_apps_scale(self):
        assert _web_scale() == _app_scale(), (
            "NtripiRadius and _radius_tokens.html disagree — change both "
            "together, the app's file first"
        )

    def test_every_document_is_a_layout(self):
        documents = {
            name
            for name, text in _templates().items()
            if re.search(r"<!doctype html", text, re.I)
        }
        assert documents == LAYOUTS, (
            "A new page layout includes _radius_tokens.html and joins LAYOUTS"
        )

    def test_every_layout_includes_the_partial(self):
        templates = _templates()
        for name in LAYOUTS:
            assert '{% include "_radius_tokens.html" %}' in templates[name], name


# ---------------------------------------------------------------------------
# TestNoTypedRadius
# ---------------------------------------------------------------------------


class TestNoTypedRadius:
    def test_every_border_radius_is_a_token(self):
        scale = _web_scale()
        typed = []
        for name, text in _templates().items():
            if name == PARTIAL.name:
                continue
            for where, value, line in _radius_declarations(text):
                if any(exempt in where for exempt in EXEMPT_SELECTORS):
                    continue
                for part in value.split():
                    token = _TOKEN.fullmatch(part)
                    if token and token.group(1) in scale:
                        continue
                    if not token and part in ("0", "50%"):
                        continue
                    typed.append(f"{name}:{line} {where} {{ border-radius: {value} }}")
                    break
        assert not typed, (
            "Take the token of the job — var(--radius-card), -field, -button, "
            "-tile, -pill… (_radius_tokens.html, mirroring NtripiRadius); a "
            "circle is 50%:\n" + "\n".join(typed)
        )

    def test_the_exemptions_still_exist(self):
        wheres = {
            where
            for text in _templates().values()
            for where, _, _ in _radius_declarations(text)
        }
        for exempt in EXEMPT_SELECTORS:
            assert any(exempt in where for where in wheres), (
                f"{exempt!r} is exempt but no longer drawn — a stale entry "
                "would let the next real one through unseen"
            )


# ---------------------------------------------------------------------------
# TestEmailButton
# ---------------------------------------------------------------------------


class TestEmailButton:
    def test_the_email_button_has_the_button_radius(self):
        source = (API / "app" / "services" / "auth_service.py").read_text()
        radii = {float(r) for r in re.findall(r"border-radius:\s*(\d+)px", source)}
        # Email clients drop CSS variables, so the email types the number —
        # this is what keeps it the button's.
        assert radii == {_app_scale()["button"]}
