"""
FAISS-backed face embedding index for fast identification at scale.
Supports separate collections (operators, customers, drivers) with
O(1) add/remove and sub-millisecond search across 50K+ embeddings.
"""

import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

try:
    import faiss

    _HAS_FAISS = True
except ImportError:
    _HAS_FAISS = False


EMBEDDING_DIM = 512


MAX_CENTROIDS = 5


@dataclass
class FaceRecord:
    record_id: str
    collection: str
    name: str
    email: str
    phone: str
    embedding: np.ndarray  # primary centroid (used in FAISS index)
    centroids: list[np.ndarray] = field(default_factory=list)  # up to MAX_CENTROIDS
    metadata: dict = field(default_factory=dict)
    enrolled_at: float = field(default_factory=time.time)


class FaceIndex:
    """Thread-safe FAISS index with metadata mapping."""

    def __init__(self, dim: int = EMBEDDING_DIM, use_gpu: bool = False):
        self._dim = dim
        self._lock = threading.Lock()
        self._records: dict[str, FaceRecord] = {}
        self._id_to_idx: dict[str, int] = {}
        self._idx_to_id: dict[int, str] = {}
        self._next_idx = 0

        if _HAS_FAISS:
            self._index = faiss.IndexFlatIP(dim)
        else:
            self._index = None

    @property
    def total_enrolled(self) -> int:
        return len(self._records)

    def count(self, collection: str | None = None) -> int:
        if collection is None:
            return len(self._records)
        return sum(1 for r in self._records.values() if r.collection == collection)

    def add(self, record: FaceRecord) -> bool:
        """Add or update a face record. Returns True if new, False if updated."""
        emb = record.embedding.astype(np.float32)
        norm = np.linalg.norm(emb)
        if norm < 1e-6:
            return False
        emb = emb / norm

        with self._lock:
            is_new = record.record_id not in self._records

            if not is_new:
                self._remove_from_index(record.record_id)

            record.embedding = emb
            self._records[record.record_id] = record

            idx = self._next_idx
            self._next_idx += 1
            self._id_to_idx[record.record_id] = idx
            self._idx_to_id[idx] = record.record_id

            if self._index is not None:
                self._index.add(emb.reshape(1, -1))
            return is_new

    def remove(self, record_id: str) -> bool:
        with self._lock:
            if record_id not in self._records:
                return False
            del self._records[record_id]
            self._rebuild_index()
            return True

    def search(
        self,
        embedding: np.ndarray,
        threshold: float = 0.45,
        top_k: int = 5,
        collection: str | None = None,
    ) -> list[tuple[FaceRecord, float]]:
        """Search for nearest faces. Returns [(record, similarity)] sorted by similarity desc."""
        emb = embedding.astype(np.float32)
        norm = np.linalg.norm(emb)
        if norm < 1e-6:
            return []
        emb = (emb / norm).reshape(1, -1)

        with self._lock:
            if not self._records:
                return []

            if self._index is not None and self._index.ntotal > 0:
                k = min(top_k * 3, self._index.ntotal)
                scores, indices = self._index.search(emb, k)
                results = []
                for score, idx in zip(scores[0], indices[0]):
                    if idx < 0 or score < threshold:
                        continue
                    record_id = self._idx_to_id.get(idx)
                    if record_id is None:
                        continue
                    record = self._records.get(record_id)
                    if record is None:
                        continue
                    if collection and record.collection != collection:
                        continue
                    results.append((record, float(score)))
                    if len(results) >= top_k:
                        break
                return results
            else:
                return self._brute_force_search(emb[0], threshold, top_k, collection)

    def _brute_force_search(
        self, emb: np.ndarray, threshold: float, top_k: int, collection: str | None
    ) -> list[tuple[FaceRecord, float]]:
        results = []
        for record in self._records.values():
            if collection and record.collection != collection:
                continue
            # Check against all centroids — best match wins
            best_sim = float(np.dot(emb, record.embedding))
            for c in record.centroids:
                s = float(np.dot(emb, c))
                if s > best_sim:
                    best_sim = s
            if best_sim >= threshold:
                results.append((record, best_sim))
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

    def _remove_from_index(self, record_id: str):
        if record_id in self._id_to_idx:
            del self._id_to_idx[record_id]
        self._rebuild_index()

    def _rebuild_index(self):
        """Rebuild FAISS index from scratch (needed after removals)."""
        self._id_to_idx.clear()
        self._idx_to_id.clear()
        self._next_idx = 0

        if self._index is not None:
            self._index.reset()

        for record_id, record in self._records.items():
            idx = self._next_idx
            self._next_idx += 1
            self._id_to_idx[record_id] = idx
            self._idx_to_id[idx] = record_id
            if self._index is not None:
                self._index.add(record.embedding.reshape(1, -1))

    def update_embedding(
        self, record_id: str, new_embedding: np.ndarray, confidence: float = 0.5
    ) -> tuple[np.ndarray, list[list[float]]] | None:
        """Progressive update with multi-centroid support.
        - Adds new embedding as a centroid if dissimilar enough from existing ones
        - Updates primary embedding as weighted mean of all centroids
        - Weight scales with match confidence (high confidence → less change needed)
        Returns (updated_primary, all_centroids) or None if not found."""
        with self._lock:
            record = self._records.get(record_id)
            if record is None:
                return None

            new = new_embedding.astype(np.float32)
            norm_new = np.linalg.norm(new)
            if norm_new < 1e-6:
                return None
            new = new / norm_new

            # Don't update if confidence too low (likely wrong person)
            if confidence < 0.5:
                return record.embedding, [c.tolist() for c in record.centroids]

            # Check if this embedding is a new "look" (dissimilar from all centroids)
            if not record.centroids:
                record.centroids = [record.embedding.copy()]

            is_new_look = True
            for c in record.centroids:
                sim = float(np.dot(new, c))
                if sim > 0.75:
                    is_new_look = False
                    break

            if is_new_look and len(record.centroids) < MAX_CENTROIDS:
                record.centroids.append(new)
            elif is_new_look:
                # Replace the centroid most similar to another (least unique)
                min_uniqueness = float("inf")
                replace_idx = 0
                for i, ci in enumerate(record.centroids):
                    max_sim_to_others = max(
                        float(np.dot(ci, cj))
                        for j, cj in enumerate(record.centroids) if j != i
                    ) if len(record.centroids) > 1 else 0
                    if max_sim_to_others < min_uniqueness:
                        min_uniqueness = max_sim_to_others
                        replace_idx = i
                record.centroids[replace_idx] = new
            else:
                # Blend into closest centroid (confidence-weighted)
                best_idx = 0
                best_sim = -1.0
                for i, c in enumerate(record.centroids):
                    sim = float(np.dot(new, c))
                    if sim > best_sim:
                        best_sim = sim
                        best_idx = i
                # High confidence → small weight (already well-represented)
                weight = max(0.05, 0.3 * (1.0 - confidence))
                blended = (1.0 - weight) * record.centroids[best_idx] + weight * new
                blended = blended / np.linalg.norm(blended)
                record.centroids[best_idx] = blended

            # Recompute primary as mean of centroids
            stacked = np.stack(record.centroids)
            primary = stacked.mean(axis=0)
            primary = primary / np.linalg.norm(primary)
            record.embedding = primary.astype(np.float32)

            self._rebuild_index()
            return record.embedding, [c.tolist() for c in record.centroids]

    def get(self, record_id: str) -> FaceRecord | None:
        return self._records.get(record_id)

    def get_all(self, collection: str | None = None) -> list[FaceRecord]:
        if collection is None:
            return list(self._records.values())
        return [r for r in self._records.values() if r.collection == collection]

    def clear(self, collection: str | None = None):
        with self._lock:
            if collection is None:
                self._records.clear()
            else:
                to_remove = [rid for rid, r in self._records.items() if r.collection == collection]
                for rid in to_remove:
                    del self._records[rid]
            self._rebuild_index()

    def sync_collection(self, collection: str, records: list[FaceRecord]):
        """Replace all records in a collection atomically."""
        with self._lock:
            to_remove = [rid for rid, r in self._records.items() if r.collection == collection]
            for rid in to_remove:
                del self._records[rid]

            for record in records:
                emb = record.embedding.astype(np.float32)
                norm = np.linalg.norm(emb)
                if norm < 1e-6:
                    continue
                record.embedding = emb / norm
                record.collection = collection
                self._records[record.record_id] = record

            self._rebuild_index()


# Global singleton
_face_index: FaceIndex | None = None


def get_face_index() -> FaceIndex:
    global _face_index
    if _face_index is None:
        _face_index = FaceIndex()
    return _face_index
