"""
Indian number plate format validation and OCR error correction.
Handles: Standard, Bharat Series, Defence, Temporary, Diplomatic,
Government, EV, Commercial, Double-line, Handwritten, Faded.

Includes position-aware correction: exploits the fixed grammar of Indian plates
(SS DD LL NNNN) to correct OCR errors based on what character TYPE is expected
at each position.
"""

import re
from .state_codes import ALL_VALID_CODES, is_valid_state_code, is_valid_district

# Common OCR character confusions: (wrong_char → possible_correct)
CHAR_SUBSTITUTIONS: dict[str, list[str]] = {
    "0": ["O", "D", "Q"],
    "O": ["0"],
    "D": ["0"],
    "Q": ["0"],
    "1": ["I", "L", "T"],
    "I": ["1"],
    "L": ["1"],
    "2": ["Z"],
    "Z": ["2"],
    "4": ["A"],
    "A": ["4"],
    "5": ["S"],
    "S": ["5"],
    "6": ["G", "B"],
    "G": ["6"],
    "8": ["B"],
    "B": ["8", "6"],
    "9": ["P"],
    "P": ["9"],
}

# Position-aware: digit→alpha and alpha→digit forced corrections
_DIGIT_TO_ALPHA: dict[str, str] = {
    "0": "O", "1": "I", "2": "Z", "3": "B", "4": "A",
    "5": "S", "6": "G", "7": "T", "8": "B", "9": "P",
}
_ALPHA_TO_DIGIT: dict[str, str] = {
    "O": "0", "D": "0", "Q": "0", "I": "1", "L": "1",
    "Z": "2", "B": "8", "S": "5", "G": "6", "T": "7",
    "A": "4", "P": "9",
}

# Plate format patterns — ordered most specific first
PLATE_FORMATS: list[tuple[str, str]] = [
    # Bharat Series: 22BH1234AB
    (r"^(\d{2})(BH)(\d{4})([A-Z]{2})$", "bharat"),
    # Diplomatic: 12CD1234 or 123CC1234
    (r"^(\d{2,3})(CD|CC|UN)(\d{1,4})$", "diplomatic"),
    # Defence: 01A12345Z (army/navy/air force)
    (r"^(\d{2})([A-Z])(\d{4,6})([A-Z])$", "defence"),
    # Government: MH01G1234
    (r"^([A-Z]{2})(\d{2})(G)(\d{4})$", "government"),
    # Temporary: MH01TC1234 or MH01TP12345
    (r"^([A-Z]{2})(\d{2})(T[CPRE]|TR|TC)(\d{4,5})$", "temporary"),
    # Electric Vehicle: MH12EV1234
    (r"^([A-Z]{2})(\d{2})(EV)([A-Z]{0,2}\d{4})$", "ev"),
    # Commercial three-letter: MH12ABC1234
    (r"^([A-Z]{2})(\d{2})([A-Z]{3})(\d{4})$", "commercial"),
    # Standard: MH12AB1234 or MH12A1234 (most common)
    (r"^([A-Z]{2})(\d{1,2})([A-Z]{1,2})(\d{1,4})$", "standard"),
    # Old format without series letter: MH121234
    (r"^([A-Z]{2})(\d{2})(\d{4})$", "old_format"),
]

# Position grammar templates for standard Indian plates
# A=alpha, D=digit — these define what's expected at each position
_GRAMMAR_TEMPLATES = [
    "AADDAADDDD",   # MH12AB1234 (standard, most common)
    "AADDADDDD",    # MH12A1234 (standard, single series)
    "AADDAAADDDD",  # MH12ABC1234 (commercial)
    "DDAADDDDAA",   # 22BH1234AB (bharat)
    "AADDADDDDDD",  # MH01G12345 (government/temp)
]


class PlateValidationResult:
    def __init__(
        self,
        text: str,
        plate_type: str = "unknown",
        confidence_boost: float = 0.0,
        state: str = "",
        district: int = 0,
        is_valid_format: bool = False,
    ):
        self.text = text
        self.plate_type = plate_type
        self.confidence_boost = confidence_boost
        self.state = state
        self.district = district
        self.is_valid_format = is_valid_format

    def __repr__(self):
        return f"PlateValidationResult(text='{self.text}', type='{self.plate_type}', valid={self.is_valid_format})"


def _position_correct(text: str) -> list[str]:
    """Apply position-aware correction using Indian plate grammar templates.
    Returns candidate corrections (including original)."""
    candidates = {text}

    for template in _GRAMMAR_TEMPLATES:
        if len(template) != len(text):
            continue

        corrected = list(text)
        valid = True
        for i, (ch, expected) in enumerate(zip(text, template)):
            if expected == "A":
                if ch.isdigit():
                    if ch in _DIGIT_TO_ALPHA:
                        corrected[i] = _DIGIT_TO_ALPHA[ch]
                    else:
                        valid = False
                        break
            elif expected == "D":
                if ch.isalpha():
                    if ch in _ALPHA_TO_DIGIT:
                        corrected[i] = _ALPHA_TO_DIGIT[ch]
                    else:
                        valid = False
                        break

        if valid:
            candidates.add("".join(corrected))

    return list(candidates)


def _try_match(text: str) -> PlateValidationResult | None:
    """Try to match text against all known plate formats."""
    for pattern, plate_type in PLATE_FORMATS:
        m = re.match(pattern, text)
        if not m:
            continue

        state = ""
        district = 0

        if plate_type in ("standard", "temporary", "government", "commercial", "old_format", "ev"):
            state = m.group(1)
            try:
                district = int(m.group(2))
            except (ValueError, IndexError):
                pass

            if not is_valid_state_code(state):
                continue
            if district > 0 and not is_valid_district(state, district):
                continue

        elif plate_type == "bharat":
            year = int(m.group(1))
            if year < 20 or year > 30:
                continue

        elif plate_type == "defence":
            pass

        elif plate_type == "diplomatic":
            pass

        return PlateValidationResult(
            text=text,
            plate_type=plate_type,
            confidence_boost=0.15,
            state=state,
            district=district,
            is_valid_format=True,
        )

    return None


def _generate_substitutions(text: str, max_depth: int = 2) -> list[str]:
    """Generate possible corrections by substituting commonly confused characters."""
    if max_depth == 0:
        return [text]

    results = set()
    results.add(text)

    for i, char in enumerate(text):
        if char in CHAR_SUBSTITUTIONS:
            for sub in CHAR_SUBSTITUTIONS[char]:
                variant = text[:i] + sub + text[i + 1:]
                results.add(variant)
                if max_depth > 1:
                    for deeper in _generate_substitutions(variant, max_depth - 1):
                        results.add(deeper)

    return list(results)


def _try_extract_from_long(text: str) -> PlateValidationResult | None:
    """Try to find a valid plate within a longer string (OCR picked up extra text).
    Prefers longest valid match."""
    if len(text) < 6:
        return None
    best: PlateValidationResult | None = None
    for start in range(len(text) - 5):
        for end in range(min(start + 13, len(text)), start + 5, -1):
            sub = text[start:end]
            result = _try_match(sub)
            if result:
                if best is None or len(result.text) > len(best.text):
                    best = result
                break
    return best


def validate_and_correct(raw_text: str) -> PlateValidationResult:
    """
    Validate plate text against all known Indian formats.
    Uses position-aware correction first (exploits plate grammar),
    then character substitution for remaining errors.
    """
    cleaned = re.sub(r"[^A-Z0-9]", "", raw_text.upper().strip())

    if not cleaned:
        return PlateValidationResult(text="", plate_type="unknown")

    # Reject impossibly long strings (max Indian plate is ~13 chars)
    if len(cleaned) > 13:
        result = _try_extract_from_long(cleaned)
        if result:
            result.confidence_boost = 0.05
            return result
        return PlateValidationResult(text=cleaned[:13], plate_type="unknown", is_valid_format=False)

    # Too short to be a plate
    if len(cleaned) < 4:
        return PlateValidationResult(text=cleaned, plate_type="unknown", is_valid_format=False)

    # Direct match
    result = _try_match(cleaned)
    if result:
        return result

    # Position-aware correction (high confidence — uses plate grammar)
    for candidate in _position_correct(cleaned):
        if candidate == cleaned:
            continue
        result = _try_match(candidate)
        if result:
            result.confidence_boost = 0.12
            return result

    # Character substitution (depth 1 — single error)
    variants = _generate_substitutions(cleaned, max_depth=1)
    for variant in variants:
        if variant == cleaned:
            continue
        result = _try_match(variant)
        if result:
            result.confidence_boost = 0.10
            return result

    # Position-correct + single substitution (combined)
    for pos_candidate in _position_correct(cleaned):
        if pos_candidate == cleaned:
            continue
        sub_variants = _generate_substitutions(pos_candidate, max_depth=1)
        for variant in sub_variants:
            if variant == pos_candidate:
                continue
            result = _try_match(variant)
            if result:
                result.confidence_boost = 0.07
                return result

    # Deeper substitution (depth 2 — two errors)
    variants = _generate_substitutions(cleaned, max_depth=2)
    for variant in variants:
        if variant == cleaned:
            continue
        result = _try_match(variant)
        if result:
            result.confidence_boost = 0.05
            return result

    # No valid format found
    return PlateValidationResult(text=cleaned, plate_type="unknown", is_valid_format=False)


def format_plate_display(text: str, plate_type: str) -> str:
    """Format plate text for display (add spaces for readability)."""
    if plate_type == "standard" or plate_type == "commercial":
        m = re.match(r"^([A-Z]{2})(\d{1,2})([A-Z]{1,3})(\d{1,4})$", text)
        if m:
            return f"{m.group(1)} {m.group(2)} {m.group(3)} {m.group(4)}"
    elif plate_type == "bharat":
        m = re.match(r"^(\d{2})(BH)(\d{4})([A-Z]{2})$", text)
        if m:
            return f"{m.group(1)} {m.group(2)} {m.group(3)} {m.group(4)}"
    return text
