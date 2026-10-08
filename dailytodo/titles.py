"""Look up the title of a web page, to suggest a name for a link resource."""
from __future__ import annotations

import html
import re
from dataclasses import dataclass
from urllib.parse import urlparse

MAX_BYTES = 256 * 1024
MAX_TITLE = 120
_TITLE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)


@dataclass(frozen=True, slots=True)
class TitleResult:
    title: str | None
    error: str | None  # short message for the user; None when the page was fetched fine


def extract_title(document: str) -> str | None:
    match = _TITLE.search(document)
    if not match:
        return None
    title = re.sub(r"\s+", " ", html.unescape(match.group(1))).strip()
    return title[:MAX_TITLE] or None


def http_error_message(code: int) -> str:
    if code == 404:
        return "Page not found (404)"
    if code in (401, 403):
        return f"Access denied ({code})"
    if code == 429:
        return "Too many requests (429)"
    if 300 <= code < 400:
        return f"Too many redirects ({code})"
    if code >= 500:
        return f"Server error ({code})"
    return f"Request failed ({code})"


def fetch_html_title(url: str, timeout: float = 4.0) -> TitleResult:
    """The <title> of an http(s) page.

    Redirects (301/302/303/307/308) are followed by urllib, so what is judged is the final
    response; an error status (4xx/5xx) or a network problem comes back as ``error``.
    """
    if urlparse(url).scheme.lower() not in ("http", "https"):
        return TitleResult(None, None)
    # urllib.request is imported here, when first needed: with http.client and email it adds
    # about 50 ms to every start of the app.
    import urllib.error
    import urllib.request

    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Marginalia)"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.headers.get_content_type() not in ("text/html", "application/xhtml+xml"):
                return TitleResult(None, "Not a web page, no title to use")
            raw = response.read(MAX_BYTES)
            charset = response.headers.get_content_charset() or "utf-8"
        title = extract_title(raw.decode(charset, errors="replace"))
        return TitleResult(title, None if title else "No page title found")
    except urllib.error.HTTPError as exc:  # before URLError: it is a subclass
        return TitleResult(None, http_error_message(exc.code))
    except (TimeoutError, OSError, ValueError, LookupError) as exc:
        reason = getattr(exc, "reason", exc)
        if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
            return TitleResult(None, "The site took too long to respond")
        return TitleResult(None, "Couldn't reach this site")