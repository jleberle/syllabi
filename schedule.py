#!/usr/bin/env python3
"""schedule.py — term calendars and schedule generation, called by new.sh.

A term calendar is calendar/<year>-<season>.conf (e.g. calendar/2027-fall.conf):
the dates that change every year, written once from the registrar's academic
calendar. new.sh reads it so a syllabus needs no date flags, and every course
in a term gets the same dates.

    start        = 2027-01-11     first day of classes
    finals       = 2027-05-03     any day in finals week (the last schedule row)
    drop_full    = 2027-01-19     100% refund deadline
    drop_partial = 2027-01-22     partial refund deadline
    sixweek      = 2027-02-24     six-week grades
    withdraw     = 2027-04-09     withdraw deadline
    withdraw_wf  = 2027-04-23     assigned W or F deadline (ends the petition period)
    no_class     = 2027-01-18 | MLK Day
    no_class     = 2027-03-15..2027-03-19 | Spring Break

Dates are YYYY-MM-DD; "#" starts a comment; a blank value counts as unset.
no_class may repeat, and takes one date or START..END followed by a label. A
week with no class Monday through Friday becomes a break row; a partial week
gets a "No class" note instead.

The standard breaks need no entry, because they follow fixed rules:
    Spring  MLK Day (third Monday of January); Spring Break (the Monday-Friday
            week of St. Patrick's Day, March 17; when that is a weekend, the
            following week -- i.e. the Monday falling between March 13 and 19)
    Fall    Labor Day (first Monday of September); Thanksgiving Break (the week
            of the fourth Thursday of November)
These match the registrar's calendars for Spring 2018-2027 (except 2021, which
had no Spring Break) and Fall 2020-2026. Before 2020 Thanksgiving was only the
Wednesday or Thursday-Friday.
    Summer  none
A no_class entry on the same day keeps its own label. `standard_breaks = off`
turns the rules off for a term whose registrar calendar departs from them; list
that term's breaks with no_class instead.

Deadlines are never inferred: a missing key leaves a labelled placeholder in the
syllabus. An unknown key is an error, so a typo cannot silently drop a deadline.

Subcommands (new.sh is the only caller):
    values   CAL                         key=value lines for the dates new.sh substitutes
    headings --weeks N [--start D] [--season S] [--online] [--cal CAL]
    table    --weeks N [--start D] [--season S] [--cal CAL] [--rows FILE]
    stub     SEASON YEAR                 a blank calendar to fill in

--weeks is only the fallback count: with a start date and a calendar `finals`,
the count comes from the calendar. --season (Spring, Fall, Summer) selects the
standard breaks.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path

DATE_KEYS = ("start", "finals", "drop_full", "drop_partial", "sixweek", "withdraw",
             "withdraw_wf")
DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri")
# Of the standard breaks, only Spring Break is the registrar's choice and could
# shift. MLK Day, Labor Day and Thanksgiving follow fixed holidays, so new.sh
# does not ask for them to be verified.
VERIFY = {"Spring Break"}
ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class CalendarError(Exception):
    pass


def warn(msg: str) -> None:
    print(f"warning: {msg}", file=sys.stderr)


@dataclass
class Calendar:
    dates: dict[str, date] = field(default_factory=dict)
    no_class: list[tuple[date, date, str]] = field(default_factory=list)
    standard_breaks: bool = True


def parse_date(text: str, where: str) -> date:
    if not ISO.match(text):
        raise CalendarError(f"{where}: {text!r} is not a YYYY-MM-DD date")
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise CalendarError(f"{where}: {text!r} is not a valid calendar date") from None


def load_calendar(path: Path) -> Calendar:
    cal = Calendar()
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        line = re.sub(r"(^|\s)#.*$", "", raw).strip()
        if not line:
            continue
        where = f"{path.name}:{n}"
        key, sep, value = (p.strip() for p in line.partition("="))
        if not sep:
            raise CalendarError(f"{where}: expected 'key = value', got {raw.strip()!r}")
        if key == "no_class":
            if value:
                cal.no_class.append(parse_no_class(value, where))
        elif key == "standard_breaks":
            if value not in ("", "on", "off"):
                raise CalendarError(f"{where}: standard_breaks is 'on' or 'off', got {value!r}")
            cal.standard_breaks = value != "off"
        elif key in DATE_KEYS:
            if key in cal.dates:
                raise CalendarError(f"{where}: {key} is set twice")
            if value:
                cal.dates[key] = parse_date(value, where)
        else:
            raise CalendarError(
                f"{where}: unknown key {key!r} (expected {', '.join(DATE_KEYS)}, no_class, standard_breaks)")
    check(cal, path.name)
    return cal


def parse_no_class(value: str, where: str) -> tuple[date, date, str]:
    span, _, label = (p.strip() for p in value.partition("|"))
    if not label:
        raise CalendarError(f"{where}: no_class needs a label, e.g. '2027-01-18 | MLK Day'")
    first, sep, last = (p.strip() for p in span.partition(".."))
    a = parse_date(first, where)
    b = parse_date(last, where) if sep else a
    if b < a:
        raise CalendarError(f"{where}: no_class range ends before it starts")
    return a, b, label


def check(cal: Calendar, name: str) -> None:
    """Catch the mistakes a wrong-year typo would otherwise ship to students."""
    start, finals = cal.dates.get("start"), cal.dates.get("finals")
    if start and start.weekday() > 4:
        warn(f"{name}: start {start} is a weekend")
    if start and finals:
        if finals < start:
            raise CalendarError(f"{name}: finals ({finals}) is before start ({start})")
        end = monday_of(finals) + timedelta(days=6)
        for key in DATE_KEYS[2:]:
            d = cal.dates.get(key)
            if d and not start <= d <= end:
                warn(f"{name}: {key} ({d}) is outside the term ({start} to {end})")
        for a, b, label in cal.no_class:
            if b < start or a > end:
                warn(f"{name}: no_class '{label}' ({a}) is outside the term")


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def month_day(d: date) -> str:
    return f"{d.strftime('%B')} {d.day}"


def short_range(a: date, b: date) -> str:
    if a.month == b.month:
        return f"{a.strftime('%b')} {a.day}–{b.day}"
    return f"{a.strftime('%b')} {a.day}–{b.strftime('%b')} {b.day}"


def week_count(start: date | None, cal: Calendar | None, fallback: int) -> int:
    if start and cal and "finals" in cal.dates:
        n = (monday_of(cal.dates["finals"]) - monday_of(start)).days // 7 + 1
        if n < 1:
            raise CalendarError(f"finals ({cal.dates['finals']}) is before start ({start})")
        return n
    return fallback


@dataclass
class Week:
    number: int
    monday: date | None
    # [first weekday index, last weekday index, label] runs of no-class days
    runs: list[list] = field(default_factory=list)

    @property
    def is_break(self) -> bool:
        return sum(r[1] - r[0] + 1 for r in self.runs) == 5

    @property
    def break_label(self) -> str:
        return " / ".join(dict.fromkeys(r[2] for r in self.runs))


def nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    first = date(year, month, 1)
    return first + timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))


def standard_breaks(season: str, year: int) -> list[tuple[date, date, str]]:
    """The breaks every term of a season has, by rule (see the module docstring)."""
    if season == "Spring":
        mlk = nth_weekday(year, 1, 0, 3)
        # The Monday between March 13 and 19: the week of March 17, rolling a
        # weekend March 17 forward (2018, 2019, 2024), never back.
        monday = nth_weekday(year, 3, 0, 1) + timedelta(weeks=1)
        while monday.day < 13:
            monday += timedelta(weeks=1)
        return [(mlk, mlk, "MLK Day"), (monday, monday + timedelta(days=4), "Spring Break")]
    if season == "Fall":
        labor = nth_weekday(year, 9, 0, 1)
        monday = monday_of(nth_weekday(year, 11, 3, 4))
        return [(labor, labor, "Labor Day"),
                (monday, monday + timedelta(days=4), "Thanksgiving Break")]
    return []


def build_weeks(start: date | None, n: int, cal: Calendar | None,
                season: str = "") -> list[Week]:
    # The calendar's own entries go first so they win a day's label.
    entries = list(cal.no_class) if cal else []
    if start and (cal is None or cal.standard_breaks):
        entries += standard_breaks(season, start.year)
    off: dict[date, str] = {}
    for a, b, label in entries:
        d = a
        while d <= b:
            if d.weekday() < 5:
                off.setdefault(d, label)
            d += timedelta(days=1)
    weeks = []
    for i in range(n):
        monday = monday_of(start) + timedelta(weeks=i) if start else None
        week = Week(i + 1, monday)
        for k in range(5 if monday else 0):
            label = off.get(monday + timedelta(days=k))
            if label is None:
                continue
            if week.runs and week.runs[-1][1] == k - 1 and week.runs[-1][2] == label:
                week.runs[-1][1] = k
            else:
                week.runs.append([k, k, label])
        weeks.append(week)
    return weeks


def rule_break_notes(start: date | None, n: int, cal: Calendar | None,
                     season: str) -> list[str]:
    """The rule-placed breaks this term got that are worth verifying (VERIFY).

    A break the calendar already names is the registrar's word, not an
    assumption, so it is left out; so is one that falls outside the term.
    """
    if not start or (cal is not None and not cal.standard_breaks):
        return []
    named: set[date] = set()
    for a, b, _ in (cal.no_class if cal else []):
        named.update(a + timedelta(days=i) for i in range((b - a).days + 1))
    first = monday_of(start)
    last = first + timedelta(weeks=n) - timedelta(days=1)
    notes = []
    for a, b, label in standard_breaks(season, start.year):
        if label not in VERIFY:
            continue
        days = [a + timedelta(days=i) for i in range((b - a).days + 1)]
        if not any(first <= d <= last and d not in named for d in days):
            continue
        when = f"{a:%a}, {a:%b} {a.day}" if a == b else short_range(a, b)
        notes.append(f"{label}: {when}")
    return notes


def day_span(first: int, last: int) -> str:
    return DAYS[first] if first == last else f"{DAYS[first]}–{DAYS[last]}"


def headings(weeks: list[Week], online: bool) -> list[str]:
    out = []
    for w in weeks:
        head = f"## Week {w.number}"
        if w.monday:
            end = w.monday + timedelta(days=6 if online else 4)
            head += f" ({month_day(w.monday)}-{month_day(end)})"
        if w.is_break:
            head += f": {w.break_label}"
        out += [head, ""]
        # An asynchronous course has no meeting days to cancel; only a full
        # break week matters to it.
        if not online and not w.is_break:
            for first, last, label in w.runs:
                out += [f"- {day_span(first, last)}: No class ({label})", ""]
    return out


def read_rows(path: Path) -> list[list[str]]:
    """Weekly rows: `| events | topic | textbook |`. Other lines are ignored."""
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3:
            raise CalendarError(
                f"{path.name}:{n}: a weekly row has 3 cells (events | topic | textbook), "
                f"found {len(cells)}")
        rows.append(cells)
    return rows


def table(weeks: list[Week], rows: list[list[str]], rows_name: str) -> list[str]:
    """Pour the weekly rows into the term's weeks.

    The last row is the finals week, and goes in the last week that has class;
    the rest fill the earlier class weeks in order, skipping break weeks. So
    the same rows serve a spring term (break after week 9) and a fall term
    (Thanksgiving week later) with only the dates and break rows moving.
    """
    teaching = [w.number - 1 for w in weeks if not w.is_break]
    slots = teaching[:-1]
    assigned: dict[int, list[str]] = {}
    if rows and teaching:
        content = rows[:-1]
        assigned[teaching[-1]] = rows[-1]
        assigned.update(zip(slots, content))
        if len(content) < len(slots):
            warn(f"{len(teaching)} class weeks but {rows_name} has {len(content) + 1} rows; "
                 f"weeks {slots[len(content)] + 1}-{slots[-1] + 1} are blank")
        elif len(content) > len(slots):
            warn(f"{len(teaching)} class weeks but {rows_name} has {len(content) + 1} rows; "
                 f"the last {len(content) - len(slots)} weekly rows before finals were dropped")

    out = []
    for w in weeks:
        dates = short_range(w.monday, w.monday + timedelta(days=4)) if w.monday else ""
        if w.is_break:
            cells = ["No class", w.break_label, ""]
        else:
            events, topic, books = assigned.get(w.number - 1, ["", "", ""])
            for first, last, label in w.runs:
                for day in DAYS[first:last + 1]:
                    if re.search(rf"\b{day}:", events):
                        warn(f"week {w.number}: {rows_name} schedules something on {day}, "
                             f"which is a no-class day ({label})")
            notes = [f"{day_span(r[0], r[1])}:&nbsp;No class ({r[2]})" for r in w.runs]
            cells = ["; ".join(notes + ([events] if events else [])), topic, books]
        out.append("| " + " | ".join([str(w.number), dates, *cells]) + " |")
    return out


def stub(season: str, year: int) -> str:
    lines = [
        f"# {season} {year} — OSU academic calendar",
        "#",
        "# Fill in from the registrar's academic calendar, as YYYY-MM-DD. Nothing here",
        "# is guessed: a blank value leaves a labelled placeholder in the syllabus.",
        "# Flags passed to new.sh (--start, --drop-full, ...) override this file.",
        "",
        "start        =    # first day of classes",
        "finals       =    # any day in finals week (sets the week count)",
        "drop_full    =    # 100% refund deadline",
        "drop_partial =    # partial refund deadline",
        "sixweek      =    # six-week grades",
        "withdraw     =    # withdraw deadline",
        "withdraw_wf  =    # assigned W or F withdrawal deadline (ends the petition period)",
        "",
        "# Standard breaks (Spring: MLK Day and the week of St. Patrick's Day; Fall: Labor",
        "# Day and Thanksgiving week) are added automatically. List any other day or week",
        "# with no class: one date, or START..END, then a label.",
        "#   no_class = 2027-10-18..2027-10-19 | Fall Break",
        "#",
        "# If the registrar's breaks differ from the standard ones, turn them off and",
        "# list this term's own:",
        "#   standard_breaks = off",
    ]
    return "\n".join(lines) + "\n"


def parse_start(text: str | None) -> date | None:
    return parse_date(text, "--start") if text else None


def main() -> int:
    ap = argparse.ArgumentParser(description="term calendars and schedule generation")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("values")
    p.add_argument("cal", type=Path)

    for name in ("headings", "table"):
        p = sub.add_parser(name)
        p.add_argument("--weeks", type=int, required=True)
        p.add_argument("--start")
        p.add_argument("--cal", type=Path)
        p.add_argument("--season", default="")
        if name == "headings":
            p.add_argument("--online", action="store_true")
        else:
            p.add_argument("--rows", type=Path)

    p = sub.add_parser("stub")
    p.add_argument("season")
    p.add_argument("year", type=int)

    args = ap.parse_args()
    try:
        if args.cmd == "stub":
            sys.stdout.write(stub(args.season, args.year))
        elif args.cmd == "values":
            cal = load_calendar(args.cal)
            for key in DATE_KEYS:
                d = cal.dates.get(key)
                if d:
                    print(f"{key}={d.isoformat() if key in ('start', 'finals') else month_day(d)}")
        else:
            cal = load_calendar(args.cal) if args.cal else None
            start = parse_start(args.start)
            count = week_count(start, cal, args.weeks)
            weeks = build_weeks(start, count, cal, args.season)
            notes = rule_break_notes(start, count, cal, args.season)
            if notes:
                print("note: placed by rule (the week of March 17), not by a calendar entry. "
                      "Verify against the registrar's calendar:", file=sys.stderr)
                for line in notes:
                    print(f"        {line}", file=sys.stderr)
            if args.cmd == "headings":
                lines = headings(weeks, args.online)
            else:
                rows = read_rows(args.rows) if args.rows and args.rows.is_file() else []
                lines = table(weeks, rows, args.rows.name if args.rows else "")
            print("\n".join(lines))
    except CalendarError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
