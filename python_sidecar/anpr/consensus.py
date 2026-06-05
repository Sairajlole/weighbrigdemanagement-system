"""
Multi-frame consensus voting for ANPR.
Accumulates plate readings from multiple cameras and frames.

Uses character-level voting: instead of requiring exact string matches,
aligns readings by position and picks the majority character at each slot.
This handles OCR confusion between visually similar chars (5↔8, 6↔8, 0↔6).
"""

import time
import uuid
from collections import Counter
from dataclasses import dataclass, field

# Characters commonly confused by OCR (visually similar)
_SIMILAR_GROUPS = [
    {"5", "8", "6"},      # curved digits
    {"0", "6", "9"},      # round digits
    {"1", "7"},           # straight digits
    {"B", "8", "6"},      # B looks like 8 or 6
    {"D", "0", "O"},      # round chars
    {"S", "5"},           # S and 5
    {"Z", "2"},           # Z and 2
    {"I", "1", "L"},      # thin verticals
]


def _are_similar_plates(a: str, b: str, max_diff: int = 2) -> bool:
    """Check if two plate strings differ by at most max_diff characters,
    considering only visually similar confusions."""
    if len(a) != len(b):
        return abs(len(a) - len(b)) <= 1 and _edit_distance_one(a, b)
    diffs = 0
    for ca, cb in zip(a, b):
        if ca != cb:
            diffs += 1
            if diffs > max_diff:
                return False
    return True


def _edit_distance_one(a: str, b: str) -> bool:
    """Check if edit distance is at most 1 (insertion/deletion)."""
    if abs(len(a) - len(b)) > 1:
        return False
    if len(a) > len(b):
        a, b = b, a
    # a is shorter or equal
    i = j = 0
    diffs = 0
    while i < len(a) and j < len(b):
        if a[i] != b[j]:
            diffs += 1
            if diffs > 1:
                return False
            j += 1
        else:
            i += 1
            j += 1
    return True


def _character_vote(readings: list[str]) -> str:
    """Vote character-by-character across aligned readings.
    All readings should be approximately the same length."""
    if not readings:
        return ""
    if len(readings) == 1:
        return readings[0]

    # Group by length — use the most common length
    length_counter = Counter(len(r) for r in readings)
    target_len = length_counter.most_common(1)[0][0]
    aligned = [r for r in readings if len(r) == target_len]

    if not aligned:
        return readings[0]

    result = []
    for pos in range(target_len):
        chars_at_pos = [r[pos] for r in aligned]
        char_counter = Counter(chars_at_pos)
        winner, count = char_counter.most_common(1)[0]
        result.append(winner)

    return "".join(result)


@dataclass
class FrameReading:
    plate_text: str
    plate_type: str
    confidence: float
    camera_id: str
    frame_quality: float
    plate_crop_b64: str = ""
    timestamp: float = field(default_factory=time.time)


@dataclass
class ConsensusSession:
    session_id: str
    readings: list[FrameReading] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    min_votes: int = 3
    max_frames: int = 15
    consensus_text: str | None = None
    consensus_type: str = "unknown"
    consensus_confidence: float = 0.0
    best_frame_quality: float = 0.0
    best_plate_crop_b64: str = ""
    is_locked: bool = False


_sessions: dict[str, ConsensusSession] = {}
_SESSION_TTL = 120.0


def _cleanup_stale():
    now = time.time()
    stale = [sid for sid, s in _sessions.items() if now - s.created_at > _SESSION_TTL]
    for sid in stale:
        del _sessions[sid]


def create_session(min_votes: int = 3, max_frames: int = 15) -> str:
    _cleanup_stale()
    session_id = uuid.uuid4().hex[:12]
    _sessions[session_id] = ConsensusSession(
        session_id=session_id,
        min_votes=min_votes,
        max_frames=max_frames,
    )
    return session_id


def add_reading(
    session_id: str,
    plate_text: str,
    plate_type: str,
    confidence: float,
    camera_id: str = "",
    frame_quality: float = 0.0,
    plate_crop_b64: str = "",
) -> dict:
    """Add a frame reading to the session. Returns current voting state."""
    session = _sessions.get(session_id)
    if session is None:
        return {"error": "session_not_found"}

    if session.is_locked:
        return get_result(session_id)

    if plate_text:
        session.readings.append(FrameReading(
            plate_text=plate_text,
            plate_type=plate_type,
            confidence=confidence,
            camera_id=camera_id,
            frame_quality=frame_quality,
            plate_crop_b64=plate_crop_b64,
        ))

    result = _check_consensus(session)
    return result


def _cluster_readings(readings: list[FrameReading]) -> list[list[FrameReading]]:
    """Group readings into clusters of similar plates (within 2 char difference)."""
    if not readings:
        return []

    clusters: list[list[FrameReading]] = []
    for reading in readings:
        placed = False
        for cluster in clusters:
            if _are_similar_plates(reading.plate_text, cluster[0].plate_text):
                cluster.append(reading)
                placed = True
                break
        if not placed:
            clusters.append([reading])

    return sorted(clusters, key=len, reverse=True)


def _check_consensus(session: ConsensusSession) -> dict:
    """Check if we have enough agreeing readings to declare a winner.
    Uses character-level voting within the largest cluster of similar readings."""
    if not session.readings:
        return {
            "session_id": session.session_id,
            "status": "scanning",
            "readings_count": 0,
            "top_candidate": None,
            "top_votes": 0,
            "locked": False,
        }

    # Prefer valid-format readings
    valid_readings = [r for r in session.readings if r.plate_text and r.plate_type != "unknown"]
    all_readings = [r for r in session.readings if r.plate_text]
    working_readings = valid_readings if valid_readings else all_readings

    if not working_readings:
        return {
            "session_id": session.session_id,
            "status": "scanning",
            "readings_count": len(session.readings),
            "top_candidate": None,
            "top_votes": 0,
            "locked": False,
        }

    # Cluster similar readings together
    clusters = _cluster_readings(working_readings)
    largest_cluster = clusters[0]
    cluster_size = len(largest_cluster)

    # Character-level vote within the largest cluster
    voted_text = _character_vote([r.plate_text for r in largest_cluster])

    # Consensus reached if cluster has enough members OR max frames exceeded
    if cluster_size >= session.min_votes or len(session.readings) >= session.max_frames:
        session.is_locked = True
        session.consensus_text = voted_text

        # Get best metadata from cluster
        best = max(largest_cluster, key=lambda r: r.confidence)
        session.consensus_type = best.plate_type
        session.consensus_confidence = best.confidence
        session.best_frame_quality = max(r.frame_quality for r in largest_cluster)
        crops_with_quality = [(r.plate_crop_b64, r.frame_quality) for r in largest_cluster if r.plate_crop_b64]
        if crops_with_quality:
            session.best_plate_crop_b64 = max(crops_with_quality, key=lambda x: x[1])[0]

        return {
            "session_id": session.session_id,
            "status": "locked",
            "plate_text": session.consensus_text,
            "plate_type": session.consensus_type,
            "confidence": round(session.consensus_confidence, 3),
            "votes": cluster_size,
            "total_readings": len(session.readings),
            "frame_quality": round(session.best_frame_quality, 1),
            "best_plate_crop_b64": session.best_plate_crop_b64,
            "locked": True,
        }

    return {
        "session_id": session.session_id,
        "status": "scanning",
        "readings_count": len(session.readings),
        "top_candidate": voted_text,
        "top_votes": cluster_size,
        "needed": session.min_votes,
        "locked": False,
    }


def get_result(session_id: str) -> dict:
    """Get the current or final result of a consensus session."""
    session = _sessions.get(session_id)
    if session is None:
        return {"error": "session_not_found"}
    return _check_consensus(session)


def delete_session(session_id: str) -> bool:
    if session_id in _sessions:
        del _sessions[session_id]
        return True
    return False
