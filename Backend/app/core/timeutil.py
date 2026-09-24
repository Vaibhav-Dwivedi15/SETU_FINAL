"""
Packet / request timestamp parsing (Block 2).

One parser for every backend consumer so freshness, AI age and audit all agree.

Accepted: strict ISO-8601 date-time with an EXPLICIT zone -- `Z` or a numeric
offset (`+05:30`) -- and 1-9 fractional-second digits (or none). This covers
everything Dart's `DateTime.toUtc().toIso8601String()` emits
(`...:00.123Z`, `...:00.123456Z`) and Python's `datetime.isoformat()`.

Rejected: timestamps without a zone (ambiguous: local vs UTC), date-only, basic
format (`20260924T...`), whitespace, lower-case `z`, anything Python's lenient
`fromisoformat` would otherwise accept. The RAW string is still what the
signature covers; this module never re-serialises it.
"""

import re
from datetime import datetime, timezone

_ISO_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$"
)


def parse_timestamp(value: str) -> datetime:
    """Return an aware UTC datetime, or raise ValueError."""
    if not isinstance(value, str) or not _ISO_RE.match(value):
        raise ValueError("timestamp must be ISO-8601 with an explicit zone (Z or +hh:mm)")
    # Python <=3.10 cannot parse 'Z' or >6 fractional digits; normalise both
    # explicitly so behaviour does not depend on the interpreter version.
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    match = re.match(r"^(.*?)(\.\d+)?([+-]\d{2}:\d{2})$", text)
    base, frac, zone = match.group(1), match.group(2) or "", match.group(3)
    frac = (frac + "000000")[:7] if frac else ""  # '.' + 6 digits (truncate, like Python 3.11+)
    parsed = datetime.fromisoformat(f"{base}{frac}{zone}")  # raises ValueError on e.g. month 13
    return parsed.astimezone(timezone.utc)


def age_seconds(sent_at: datetime, now: datetime | None = None) -> float:
    """Seconds since sent_at (negative if it is in the future)."""
    now = now or datetime.now(timezone.utc)
    return (now - sent_at).total_seconds()
