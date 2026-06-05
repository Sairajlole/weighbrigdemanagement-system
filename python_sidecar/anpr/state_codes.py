"""Valid Indian RTO state codes and district ranges."""

STATE_CODES: dict[str, str] = {
    "AN": "Andaman and Nicobar",
    "AP": "Andhra Pradesh",
    "AR": "Arunachal Pradesh",
    "AS": "Assam",
    "BR": "Bihar",
    "CG": "Chhattisgarh",
    "CH": "Chandigarh",
    "DD": "Dadra Nagar Haveli and Daman Diu",
    "DL": "Delhi",
    "GA": "Goa",
    "GJ": "Gujarat",
    "HP": "Himachal Pradesh",
    "HR": "Haryana",
    "JH": "Jharkhand",
    "JK": "Jammu and Kashmir",
    "KA": "Karnataka",
    "KL": "Kerala",
    "LA": "Ladakh",
    "MH": "Maharashtra",
    "ML": "Meghalaya",
    "MN": "Manipur",
    "MP": "Madhya Pradesh",
    "MZ": "Mizoram",
    "NL": "Nagaland",
    "OD": "Odisha",
    "PB": "Punjab",
    "PY": "Puducherry",
    "RJ": "Rajasthan",
    "SK": "Sikkim",
    "TN": "Tamil Nadu",
    "TR": "Tripura",
    "TS": "Telangana",
    "UK": "Uttarakhand",
    "UP": "Uttar Pradesh",
    "WB": "West Bengal",
}

# Legacy codes still found on older vehicles
LEGACY_CODES: dict[str, str] = {
    "OR": "Odisha (old)",
    "UA": "Uttarakhand (old)",
    "DN": "Dadra and Nagar Haveli (old)",
}

ALL_VALID_CODES = set(STATE_CODES.keys()) | set(LEGACY_CODES.keys())

# Maximum known district numbers per state (approximate upper bounds)
MAX_DISTRICT: dict[str, int] = {
    "AN": 5, "AP": 39, "AR": 22, "AS": 34, "BR": 99, "CG": 30,
    "CH": 4, "DD": 4, "DL": 99, "GA": 12, "GJ": 99, "HP": 99,
    "HR": 99, "JH": 23, "JK": 22, "KA": 72, "KL": 99, "LA": 4,
    "MH": 99, "ML": 10, "MN": 7, "MP": 99, "MZ": 8, "NL": 10,
    "OD": 35, "PB": 99, "PY": 5, "RJ": 99, "SK": 8, "TN": 99,
    "TR": 8, "TS": 38, "UK": 20, "UP": 99, "WB": 99,
    "OR": 35, "UA": 20, "DN": 4,
}


def is_valid_state_code(code: str) -> bool:
    return code.upper() in ALL_VALID_CODES


def is_valid_district(state: str, district: int) -> bool:
    max_d = MAX_DISTRICT.get(state.upper(), 99)
    return 1 <= district <= max_d
