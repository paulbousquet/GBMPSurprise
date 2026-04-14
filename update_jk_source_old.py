from __future__ import annotations

import argparse
import calendar
import csv
import io
import re
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from html import unescape
from pathlib import Path
from urllib.request import Request, urlopen

import openpyxl


DEFAULT_USMPD_URL = "https://www.frbsf.org/wp-content/uploads/USMPD.xlsx"
DEFAULT_CALENDAR_URL = "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm"
USER_AGENT = "Mozilla/5.0"

CSV_HEADERS = [
    "Date",
    "Unscheduled",
    "fomc_latest",
    "main",
    "MP1",
    "MP2",
    "FF1",
    "FF2",
    "FF3",
    "FF4",
    "FF5",
    "FF6",
    "ED1",
    "ED2",
    "ED3",
    "ED4",
    "ED5",
    "ED6",
    "ED7",
    "ED8",
    "UST3M",
    "UST6M",
    "UST2Y",
    "UST5Y",
    "UST10Y",
    "UST30Y",
    "SP500",
    "SPFUT",
    "EURUSD",
    "FF4_MR",
    "NFP_SURP",
    "NFP_12M",
    "SP500_3M",
    "SLOPE_3M",
    "BCOM_3M",
    "TR_SKEW",
    "SEP",
    "PC",
    "OIS1Y",
    "OIS2Y",
    "TIPS5Y",
    "TIPS10Y",
    "TIPS30Y",
    "DXY",
    "USDJPY",
    "cycle",
    "tffrm",
]

USMPD_DIRECT_COLUMNS = [
    "MP1",
    "MP2",
    "FF1",
    "FF2",
    "FF3",
    "FF4",
    "FF5",
    "FF6",
    "ED1",
    "ED2",
    "ED3",
    "ED4",
    "ED5",
    "ED6",
    "ED7",
    "ED8",
    "UST3M",
    "UST6M",
    "UST2Y",
    "UST5Y",
    "UST10Y",
    "UST30Y",
    "SP500",
    "SPFUT",
    "EURUSD",
    "SEP",
    "PC",
    "OIS1Y",
    "OIS2Y",
    "TIPS5Y",
    "TIPS10Y",
    "TIPS30Y",
    "DXY",
    "USDJPY",
]

REAL_DATA_COLUMNS = USMPD_DIRECT_COLUMNS

CONTROLLED_COLUMNS = {
    "Date",
    "Unscheduled",
    "fomc_latest",
    "main",
    *USMPD_DIRECT_COLUMNS,
}

MONTH_NUMBERS = {
    month_name: month_number
    for month_number, month_name in enumerate(calendar.month_name)
    if month_name
}

YEAR_PANEL_PATTERN = re.compile(
    r'<div class="panel panel-default">\s*<div class="panel-heading">\s*'
    r'<h4><a id="[^"]+">(?P<year>\d{4}) FOMC Meetings</a></h4></div>'
    r'(?P<body>.*?)(?=<div class="panel panel-default">\s*<div class="panel-heading">\s*'
    r'<h4><a id="[^"]+">\d{4} FOMC Meetings</a></h4></div>|Last Update:)',
    re.S,
)

MEETING_PATTERN = re.compile(
    r'fomc-meeting__month[^>]*><strong>(?P<month>[^<]+)</strong>.*?'
    r'fomc-meeting__date[^>]*>(?P<dates>[^<]+)</div>',
    re.S,
)


def parse_args() -> argparse.Namespace:
    repo_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description=(
            "Update jk_source_old.csv using the remote FRBSF USMPD workbook and "
            "add future scheduled FOMC placeholder rows when a new data year begins."
        )
    )
    parser.add_argument("--csv", type=Path, default=repo_dir / "jk_source_old.csv")
    parser.add_argument("--sheet", default="Monetary Events")
    parser.add_argument("--usmpd-url", default=DEFAULT_USMPD_URL)
    parser.add_argument("--calendar-url", default=DEFAULT_CALENDAR_URL)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def parse_mdy(value: str) -> date:
    return datetime.strptime(value, "%m/%d/%Y").date()


def format_mdy(value: date | datetime) -> str:
    if isinstance(value, datetime):
        value = value.date()
    return f"{value.month}/{value.day}/{value.year}"


def format_number(value: object) -> str:
    if value is None:
        return ""

    quantized = Decimal(str(value)).quantize(
        Decimal("0.000000001"), rounding=ROUND_HALF_UP
    )
    if quantized == 0:
        return "0"

    text = format(quantized, "f").rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def normalize_excel_date(value: object) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    raise ValueError(f"Unsupported Excel date value: {value!r}")


def blank_row() -> dict[str, str]:
    return {header: "" for header in CSV_HEADERS}


def download_bytes(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=60) as response:
        return response.read()


def read_csv_rows(csv_path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with csv_path.open("r", newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        if fieldnames != CSV_HEADERS:
            raise ValueError(f"Unexpected CSV header in {csv_path}")

        rows = list(reader)
        if not rows:
            raise ValueError(f"{csv_path} has no data rows")

    return fieldnames, rows


def write_csv_rows(
    csv_path: Path, fieldnames: list[str], rows: list[dict[str, str]]
) -> None:
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def row_has_real_data(row: dict[str, str]) -> bool:
    return any((row.get(column, "") or "").strip() for column in REAL_DATA_COLUMNS)


def latest_real_data_date(rows: list[dict[str, str]]) -> date:
    for row in reversed(rows):
        if row_has_real_data(row):
            return parse_mdy(row["Date"])
    raise ValueError("Could not find a row with real data in jk_source_old.csv")


def load_usmpd_records(
    workbook_bytes: bytes, sheet_name: str
) -> dict[date, dict[str, object]]:
    workbook = openpyxl.load_workbook(
        io.BytesIO(workbook_bytes), read_only=True, data_only=True
    )
    worksheet = workbook[sheet_name]

    rows = worksheet.iter_rows(values_only=True)
    excel_headers = next(rows)
    if excel_headers is None:
        raise ValueError(f"Worksheet '{sheet_name}' has no rows")

    missing_columns = [
        column for column in ["Date", *USMPD_DIRECT_COLUMNS] if column not in excel_headers
    ]
    if missing_columns:
        raise ValueError(
            f"Worksheet '{sheet_name}' is missing columns: {', '.join(missing_columns)}"
        )

    records: dict[date, dict[str, object]] = {}
    for raw_row in rows:
        record = dict(zip(excel_headers, raw_row))
        if not record.get("Date"):
            continue

        event_date = normalize_excel_date(record["Date"])
        records[event_date] = record

    workbook.close()
    return records


def build_usmpd_row(
    record: dict[str, object], existing_row: dict[str, str] | None = None
) -> dict[str, str]:
    event_date = normalize_excel_date(record["Date"])
    row = blank_row() if existing_row is None else existing_row.copy()

    row["Date"] = format_mdy(event_date)
    row["Unscheduled"] = "0"
    row["fomc_latest"] = row["Date"]
    row["main"] = "0"

    for column in USMPD_DIRECT_COLUMNS:
        row[column] = format_number(record.get(column))

    return row


def build_placeholder_row(event_date: date) -> dict[str, str]:
    row = blank_row()
    row["Date"] = format_mdy(event_date)
    row["Unscheduled"] = "0"
    row["fomc_latest"] = row["Date"]
    row["main"] = "0"
    return row


def sync_scheduled_row_fields(existing_row: dict[str, str], meeting_date: date) -> bool:
    changed = False
    date_text = format_mdy(meeting_date)
    for column, value in (
        ("Date", date_text),
        ("Unscheduled", "0"),
        ("fomc_latest", date_text),
        ("main", "0"),
    ):
        if existing_row.get(column, "") != value:
            existing_row[column] = value
            changed = True
    return changed


def fetch_schedule_for_year(year: int, calendar_url: str) -> list[date]:
    html = download_bytes(calendar_url).decode("utf-8", errors="replace")

    panel_body = None
    for match in YEAR_PANEL_PATTERN.finditer(html):
        if int(match.group("year")) == year:
            panel_body = match.group("body")
            break

    if panel_body is None:
        raise ValueError(f"Could not find {year} FOMC schedule on {calendar_url}")

    meeting_dates: list[date] = []
    for match in MEETING_PATTERN.finditer(panel_body):
        month_text = unescape(match.group("month")).strip()
        date_text = unescape(match.group("dates")).strip()
        meeting_dates.append(parse_scheduled_meeting_last_day(year, month_text, date_text))

    if not meeting_dates:
        raise ValueError(f"No FOMC meetings found for {year} on {calendar_url}")

    return meeting_dates


def parse_scheduled_meeting_last_day(year: int, month_text: str, date_text: str) -> date:
    month_parts = [part.strip() for part in month_text.split("/") if part.strip()]
    if not month_parts:
        raise ValueError(f"Could not parse month text: {month_text!r}")

    day_numbers = [int(value) for value in re.findall(r"\d+", date_text)]
    if not day_numbers:
        raise ValueError(f"Could not parse meeting days: {date_text!r}")

    last_month = month_parts[-1]
    if last_month not in MONTH_NUMBERS:
        raise ValueError(f"Unsupported month label: {month_text!r}")

    return date(year, MONTH_NUMBERS[last_month], day_numbers[-1])


def merge_controlled_fields(
    existing_row: dict[str, str], new_row: dict[str, str]
) -> bool:
    changed = False
    for column in CONTROLLED_COLUMNS:
        if existing_row.get(column, "") != new_row.get(column, ""):
            existing_row[column] = new_row.get(column, "")
            changed = True
    return changed


def next_month_key(year: int, month: int) -> tuple[int, int]:
    if month == 12:
        return year + 1, 1
    return year, month + 1


def apply_mp1_ff2_rule(rows: list[dict[str, str]]) -> list[str]:
    parsed_dates = [parse_mdy(row["Date"]) for row in rows]
    months_present = {(parsed.year, parsed.month) for parsed in parsed_dates}

    changed_dates: list[str] = []
    for row, parsed in zip(rows, parsed_dates):
        if parsed.year < 1993 or row.get("Unscheduled", "").strip() != "0":
            continue

        if next_month_key(parsed.year, parsed.month) in months_present:
            continue

        ff2_value = row.get("FF2", "")
        if row.get("MP1", "") != ff2_value:
            row["MP1"] = ff2_value
            changed_dates.append(row["Date"])

    return changed_dates


def apply_new_usmpd_records(
    rows: list[dict[str, str]],
    usmpd_records: dict[date, dict[str, object]],
    since_date: date,
) -> tuple[list[date], list[str], list[str]]:
    row_by_date = {parse_mdy(row["Date"]): row for row in rows}
    new_dates = sorted(meeting_date for meeting_date in usmpd_records if meeting_date > since_date)

    refreshed_dates: list[str] = []
    appended_dates: list[str] = []
    for meeting_date in new_dates:
        existing_row = row_by_date.get(meeting_date)
        new_row = build_usmpd_row(usmpd_records[meeting_date], existing_row)
        if existing_row is None:
            rows.append(new_row)
            row_by_date[meeting_date] = rows[-1]
            appended_dates.append(format_mdy(meeting_date))
            continue

        if merge_controlled_fields(existing_row, new_row):
            refreshed_dates.append(format_mdy(meeting_date))

    return new_dates, refreshed_dates, appended_dates


def ensure_schedule_rows(
    rows: list[dict[str, str]],
    years: list[int],
    calendar_url: str,
) -> tuple[list[str], list[str]]:
    if not years:
        return [], []

    row_by_date = {parse_mdy(row["Date"]): row for row in rows}
    refreshed_dates: list[str] = []
    appended_dates: list[str] = []

    for year in years:
        for meeting_date in fetch_schedule_for_year(year, calendar_url):
            existing_row = row_by_date.get(meeting_date)
            if existing_row is None:
                new_row = build_placeholder_row(meeting_date)
                rows.append(new_row)
                row_by_date[meeting_date] = rows[-1]
                appended_dates.append(format_mdy(meeting_date))
                continue

            if sync_scheduled_row_fields(existing_row, meeting_date):
                refreshed_dates.append(format_mdy(meeting_date))

    return refreshed_dates, appended_dates


def schedule_years_to_seed(previous_real_date: date, new_real_dates: list[date]) -> list[int]:
    if not new_real_dates:
        return []

    latest_new_real_year = max(new_real_dates).year
    return list(range(previous_real_date.year + 2, latest_new_real_year + 2))


def main() -> int:
    args = parse_args()
    csv_path = args.csv.resolve()

    if not csv_path.exists():
        raise FileNotFoundError(f"CSV file not found: {csv_path}")

    fieldnames, rows = read_csv_rows(csv_path)
    previous_real_date = latest_real_data_date(rows)

    usmpd_bytes = download_bytes(args.usmpd_url)
    usmpd_records = load_usmpd_records(usmpd_bytes, args.sheet)

    new_real_dates, usmpd_refreshed, usmpd_appended = apply_new_usmpd_records(
        rows, usmpd_records, previous_real_date
    )

    if not new_real_dates:
        print(f"No new USMPD rows found after {format_mdy(previous_real_date)}.")
        return 0

    placeholder_years = schedule_years_to_seed(previous_real_date, new_real_dates)
    schedule_refreshed, schedule_appended = ensure_schedule_rows(
        rows, placeholder_years, args.calendar_url
    )
    mp1_ff2_dates = apply_mp1_ff2_rule(rows)

    if args.dry_run:
        if usmpd_refreshed:
            print(
                f"Would refresh {len(usmpd_refreshed)} USMPD row(s): "
                f"{', '.join(usmpd_refreshed)}"
            )
        if usmpd_appended:
            print(
                f"Would append {len(usmpd_appended)} USMPD row(s): "
                f"{', '.join(usmpd_appended)}"
            )
        if schedule_refreshed:
            print(
                f"Would refresh {len(schedule_refreshed)} scheduled row(s): "
                f"{', '.join(schedule_refreshed)}"
            )
        if schedule_appended:
            print(
                f"Would append {len(schedule_appended)} blank scheduled row(s): "
                f"{', '.join(schedule_appended)}"
            )
        if mp1_ff2_dates:
            print(
                f"Would replace MP1 with FF2 in {len(mp1_ff2_dates)} row(s): "
                f"{', '.join(mp1_ff2_dates)}"
            )
        return 0

    write_csv_rows(csv_path, fieldnames, rows)

    if usmpd_refreshed:
        print(
            f"Refreshed {len(usmpd_refreshed)} USMPD row(s): "
            f"{', '.join(usmpd_refreshed)}"
        )
    if usmpd_appended:
        print(
            f"Appended {len(usmpd_appended)} USMPD row(s): "
            f"{', '.join(usmpd_appended)}"
        )
    if schedule_refreshed:
        print(
            f"Refreshed {len(schedule_refreshed)} scheduled row(s): "
            f"{', '.join(schedule_refreshed)}"
        )
    if schedule_appended:
        print(
            f"Appended {len(schedule_appended)} blank scheduled row(s): "
            f"{', '.join(schedule_appended)}"
        )
    if mp1_ff2_dates:
        print(
            f"Replaced MP1 with FF2 in {len(mp1_ff2_dates)} row(s): "
            f"{', '.join(mp1_ff2_dates)}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
