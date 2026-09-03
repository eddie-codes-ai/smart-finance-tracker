"""
Every timezone decision in the backend lives here.

The database stores naive datetimes that are always UTC. Anything that answers a
*calendar* question — which month is this transaction in, which day did this
spending fall on, what is today — has to be asked in the user's own zone, not
UTC. Mixing the two is what made transactions logged between 00:00 and 03:00 EAT
disappear from the current month.

Two rules keep that from coming back:

1. **Zone names, never offsets.** A New York user asking in July for last
   November's figures needs EST (-5), while their device reports EDT (-4). Only
   an IANA name lets us work out which offset applied *at that date*. Kenya
   happens to have no DST, which is why a fixed offset was survivable there and
   would be wrong almost anywhere else.

2. **`tz` is a required argument, never a module default.** A forgotten
   argument fails loudly here instead of quietly computing Nairobi months for a
   user in Toronto — which is precisely the bug this module exists to prevent.

The user's zone is their stored *home* zone (`User.timezone`), not their device's
current one, so that flying somewhere does not silently re-bucket their history.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Optional, Tuple
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones

# Used for users who have no zone recorded, and as the fallback for a name the
# tz database does not recognise.
DEFAULT_TIMEZONE_NAME = "Africa/Nairobi"

__all__ = [
    "DEFAULT_TIMEZONE_NAME",
    "default_timezone",
    "resolve_timezone",
    "is_valid_timezone",
    "known_timezones",
    "utc_now",
    "to_tz",
    "now_in",
    "today_in",
    "local_date_of",
    "month_range_utc",
    "iso_utc",
]


def default_timezone() -> ZoneInfo:
    return ZoneInfo(DEFAULT_TIMEZONE_NAME)


def resolve_timezone(name: Optional[str]) -> ZoneInfo:
    """
    Turn a stored zone name into a tzinfo, falling back rather than raising.

    A bad or missing name must never take an endpoint down; the user simply gets
    the default zone until they correct it.
    """
    if not name:
        return default_timezone()
    try:
        return ZoneInfo(name.strip())
    except (ZoneInfoNotFoundError, ValueError, KeyError):
        return default_timezone()


def is_valid_timezone(name: Optional[str]) -> bool:
    """Whether the tz database recognises this name. Used to validate input."""
    if not name or not name.strip():
        return False
    try:
        ZoneInfo(name.strip())
        return True
    except (ZoneInfoNotFoundError, ValueError, KeyError):
        return False


def known_timezones() -> list:
    """Every IANA name this server accepts, sorted. Served to the app's picker
    so the list can never drift from what the backend will actually take."""
    return sorted(available_timezones())


def utc_now() -> datetime:
    """
    Current UTC time as a naive datetime, matching how the columns store it.

    Replaces datetime.utcnow(), which is deprecated from Python 3.12.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def to_tz(moment: datetime, tz) -> datetime:
    """Interpret a stored (naive UTC) datetime in the given zone."""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(tz)


def now_in(tz) -> datetime:
    """Current local time in the given zone, timezone-aware."""
    return datetime.now(tz)


def today_in(tz) -> date:
    """Today's date in the given zone, which is not always today's date in UTC."""
    return now_in(tz).date()


def local_date_of(moment: datetime, tz) -> date:
    """
    The local calendar day a stored timestamp falls on.

    Used to bucket spending per day: an expense at 23:00 local is stored as
    20:00 UTC the same day, but one at 01:00 local is stored as 22:00 UTC the
    *previous* day, and grouping on the raw UTC date files it against the wrong
    day.
    """
    return to_tz(moment, tz).date()


def month_range_utc(year: int, month: int, tz) -> Tuple[datetime, datetime]:
    """
    The naive-UTC half-open bounds [start, end) of a local calendar month.

    For Africa/Nairobi, September 2026 runs from 2026-08-31 21:00 UTC to
    2026-09-30 21:00 UTC. For America/Toronto the same month runs from
    2026-09-01 04:00 to 2026-10-01 04:00 — and the offset differs either side of
    a DST change, which is why this takes a zone and not a number.

    Half-open so a transaction landing exactly on a boundary belongs to
    precisely one month.
    """
    start_local = datetime(year, month, 1, tzinfo=tz)
    if month == 12:
        end_local = datetime(year + 1, 1, 1, tzinfo=tz)
    else:
        end_local = datetime(year, month + 1, 1, tzinfo=tz)
    return (
        start_local.astimezone(timezone.utc).replace(tzinfo=None),
        end_local.astimezone(timezone.utc).replace(tzinfo=None),
    )


def iso_utc(moment: Optional[datetime]) -> Optional[str]:
    """
    Serialize a stored timestamp with an explicit UTC marker.

    Without the trailing "Z" the client's DateTime.parse() treats the string as
    local time and applies no conversion, which is why every timestamp in the
    app once displayed three hours early. Only for real timestamps — plain
    calendar dates (a goal due date, a semester start) carry no timezone and
    must keep using .isoformat().
    """
    if moment is None:
        return None
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment.isoformat() + "Z"
