
import numpy as np
import pandas as pd

DATA_PATH = "data.csv"
SCHEDULE_PATH = "Book11.csv"
OUTPUT_PATH = "matched_dataset.csv"


def decimal_year_to_datetime(values: pd.Series) -> pd.Series:
    years = np.floor(values).astype(int)
    fractions = values - years
    is_leap = ((years % 4 == 0) & ((years % 100 != 0) | (years % 400 == 0)))
    days_in_year = np.where(is_leap, 366, 365)
    day_offsets = fractions * days_in_year
    base_dates = pd.to_datetime(years.astype(str) + "-01-01")
    return base_dates + pd.to_timedelta(day_offsets, unit="D")


data = pd.read_csv(DATA_PATH, header=None, names=["x_year", "y"])
data = data[data["x_year"] < 2020]
schedule = pd.read_csv(SCHEDULE_PATH)

schedule["schedstr"] = pd.to_datetime(schedule["schedstr"], errors="coerce")
schedule = schedule.dropna(subset=["schedstr"])

data["x_date"] = decimal_year_to_datetime(data["x_year"])
data = data.dropna(subset=["x_date"]).sort_values("x_date")
schedule = schedule.sort_values("schedstr")

matched = pd.merge_asof(
    schedule,
    data,
    left_on="schedstr",
    right_on="x_date",
    direction="nearest",
)

matched = matched[
    [
        "schedstr",
        "MP1",
        "FF1",
        "FF2",
        "FF3",
        "FF4",
        "ED1",
        "ED2",
        "ED3",
        "ED4",
        "x_year",
        "x_date",
        "y",
    ]
]

matched.to_csv(OUTPUT_PATH, index=False)
