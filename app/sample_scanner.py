#!/usr/bin/env python3
"""Scan built-in samples and generate a compatibility-preserving manifest.

Manifest goals:
1) Keep shipped canonical IDs stable across path moves/renames.
2) Keep compatibility with legacy hash-12 IDs via aliases.
3) Fail loudly when a shipped built-in sample disappears or changes identity.
"""

import argparse
import hashlib
import json
import os
import re
import time
from urllib.parse import quote
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set

# Supported audio file extensions
AUDIO_EXTENSIONS = {".wav", ".mp3", ".aiff", ".aif", ".flac", ".ogg", ".m4a"}


def generate_file_hash(file_path: Path) -> str:
    """Generate a lowercase SHA-256 hash for a file."""
    hash_sha256 = hashlib.sha256()

    try:
        with open(file_path, "rb") as file_obj:
            for chunk in iter(lambda: file_obj.read(4096), b""):
                hash_sha256.update(chunk)
        return hash_sha256.hexdigest()
    except Exception as exc:
        print(f"Error hashing file {file_path}: {exc}")
        return ""


def _slug_segment(value: str) -> str:
    # Keep a deterministic marker for note names (C# -> c___sharp___).
    value = value.replace("#", "hypnosharptoken")
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value)
    value = value.replace("hypnosharptoken", "___sharp___")
    return value.strip("_")


def _stable_builtin_id(samples_dir: Path, file_path: Path) -> str:
    relative = file_path.relative_to(samples_dir)
    no_ext = relative.with_suffix("")
    parts = [_slug_segment(part) for part in no_ext.parts if _slug_segment(part)]
    if not parts:
        return "builtin.unknown"
    return "builtin." + ".".join(parts)


def _normalize_path(path_value: str) -> str:
    return path_value.replace("\\", "/")


def _sorted_unique_strings(values: Iterable[str]) -> List[str]:
    cleaned = {value.strip() for value in values if isinstance(value, str) and value.strip()}
    return sorted(cleaned)


def _load_manifest(manifest_path: Path) -> Dict[str, Any]:
    if not manifest_path.exists():
        return {}

    try:
        with open(manifest_path, "r", encoding="utf-8") as file_obj:
            decoded = json.load(file_obj)
        if isinstance(decoded, dict):
            return decoded
    except Exception as exc:
        raise ValueError(f"Failed to read previous manifest {manifest_path}: {exc}") from exc

    raise ValueError(f"Previous manifest {manifest_path} is not a JSON object.")


def _manifest_samples(manifest: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    raw_samples = manifest.get("samples", {})
    if not isinstance(raw_samples, dict):
        return {}

    samples: Dict[str, Dict[str, Any]] = {}
    for sample_id, raw_entry in raw_samples.items():
        if isinstance(sample_id, str) and isinstance(raw_entry, dict):
            samples[sample_id] = dict(raw_entry)
    return samples


def _entry_sha256(entry: Dict[str, Any]) -> Optional[str]:
    value = entry.get("sha256")
    if isinstance(value, str):
        normalized = value.strip().lower()
        if len(normalized) == 64:
            return normalized
    return None


def _entry_legacy_hash(entry: Dict[str, Any]) -> Optional[str]:
    value = entry.get("legacy_hash_12")
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized:
            return normalized
    return None


def _entry_path(entry: Dict[str, Any]) -> Optional[str]:
    value = entry.get("path")
    if isinstance(value, str):
        normalized = _normalize_path(value.strip())
        if normalized:
            return normalized
    return None


def _manifest_relative_path(samples_dir: Path, file_path: Path) -> str:
    base_dir = samples_dir.parent if samples_dir.parent != Path("") else Path(".")
    return _normalize_path(str(file_path.relative_to(base_dir)))


def _safe_asset_key_from_path(relative_file_path: str) -> str:
    # Keep slash separators, encode per segment for safer iOS bundle lookup.
    return "/".join(quote(segment, safe="._-") for segment in relative_file_path.split("/"))


def _prettify_label(raw: str) -> str:
    if not raw:
        return raw
    text = raw
    text = text.replace("___sharp___", "#")
    text = text.replace("_", " ")
    text = re.sub(r"(?i)\b([a-g])\s*sharp\s*(\d)\b", lambda m: f"{m.group(1).upper()}#{m.group(2)}", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _display_name_from_file(file_path: Path) -> str:
    return _prettify_label(file_path.stem)


def _display_path_from_file(samples_dir: Path, file_path: Path) -> str:
    rel_parent = file_path.relative_to(samples_dir).parent
    if str(rel_parent) == ".":
        return ""
    return "/".join(_prettify_label(part) for part in rel_parent.parts)


def _append_index(index: Dict[str, List[str]], key: Optional[str], sample_id: str) -> None:
    if not key:
        return
    index.setdefault(key, []).append(sample_id)


def _single_candidate(
    index: Dict[str, List[str]],
    key: Optional[str],
    *,
    collision_label: str,
) -> Optional[str]:
    if not key:
        return None
    candidates = sorted(set(index.get(key, [])))
    if not candidates:
        return None
    if len(candidates) > 1:
        raise ValueError(
            f"Previous manifest has ambiguous {collision_label} '{key}' for ids: "
            + ", ".join(candidates)
        )
    return candidates[0]


def _workspace_root_for_samples(samples_dir_path: Path) -> Path:
    parent = samples_dir_path.parent
    return parent if str(parent) not in ("", ".") else Path(".")


def _path_exists_under_workspace(relative_path: str, workspace_root: Path) -> bool:
    path_obj = Path(relative_path)
    if path_obj.is_absolute():
        try:
            return path_obj.is_file()
        except OSError:
            return False
    try:
        return (workspace_root / path_obj).is_file()
    except OSError:
        return False


def _allowed_removals_when_previous_file_gone(
    previous_samples: Dict[str, Dict[str, Any]],
    workspace_root: Path,
    output_sample_ids: Set[str],
) -> Set[str]:
    """Allow dropping a shipped id when its manifest path no longer exists (deleted duplicate, etc.)."""
    allowed: Set[str] = set()
    for sample_id, entry in previous_samples.items():
        if sample_id in output_sample_ids:
            continue
        sample_path = _entry_path(entry)
        if not sample_path:
            allowed.add(sample_id)
            continue
        if not _path_exists_under_workspace(sample_path, workspace_root):
            allowed.add(sample_id)
    return allowed


def _disambiguate_candidates(
    candidates: List[str],
    previous_samples: Dict[str, Dict[str, Any]],
    relative_file_path: str,
    file_hash: str,
) -> Optional[str]:
    """When multiple manifest entries share legacy_hash_12 or full sha256, match by path/hash."""
    if len(candidates) == 1:
        return candidates[0]

    path_matches = [
        cid
        for cid in candidates
        if _entry_path(previous_samples.get(cid, {})) == relative_file_path
    ]
    if len(path_matches) == 1:
        return path_matches[0]

    hash_and_path = [
        cid
        for cid in candidates
        if _entry_sha256(previous_samples.get(cid, {})) == file_hash
        and _entry_path(previous_samples.get(cid, {})) == relative_file_path
    ]
    if len(hash_and_path) == 1:
        return hash_and_path[0]

    hash_only = [
        cid
        for cid in candidates
        if _entry_sha256(previous_samples.get(cid, {})) == file_hash
    ]
    if len(hash_only) == 1:
        return hash_only[0]

    return None


def _resolve_index_lookup(
    index: Dict[str, List[str]],
    key: Optional[str],
    *,
    collision_label: str,
    previous_samples: Dict[str, Dict[str, Any]],
    relative_file_path: str,
    file_hash: str,
) -> Optional[str]:
    if not key:
        return None
    candidates = sorted(set(index.get(key, [])))
    if not candidates:
        return None
    resolved = _disambiguate_candidates(
        candidates, previous_samples, relative_file_path, file_hash
    )
    if resolved:
        return resolved
    if len(candidates) > 1:
        raise ValueError(
            f"Previous manifest has ambiguous {collision_label} '{key}' for ids: "
            + ", ".join(candidates)
            + ". Cannot match this file to a single canonical id."
        )
    return candidates[0]


def _entry_id_list(entry: Dict[str, Any], field: str) -> List[str]:
    value = entry.get(field)
    if isinstance(value, list):
        return _sorted_unique_strings(value)
    return []


def _previous_indexes(
    previous_samples: Dict[str, Dict[str, Any]],
    workspace_root: Path,
) -> Dict[str, Dict[str, List[str]]]:
    by_sha256: Dict[str, List[str]] = {}
    by_legacy_hash: Dict[str, List[str]] = {}
    by_path: Dict[str, List[str]] = {}

    for sample_id, entry in previous_samples.items():
        _append_index(by_sha256, _entry_sha256(entry), sample_id)
        _append_index(by_legacy_hash, _entry_legacy_hash(entry), sample_id)
        sample_path = _entry_path(entry)
        if sample_path and _path_exists_under_workspace(sample_path, workspace_root):
            _append_index(by_path, sample_path, sample_id)

    return {
        "by_sha256": by_sha256,
        "by_legacy_hash": by_legacy_hash,
        "by_path": by_path,
    }


def _choose_canonical_id(
    *,
    path_derived_id: str,
    relative_file_path: str,
    file_hash: str,
    legacy_hash_12: str,
    previous_samples: Dict[str, Dict[str, Any]],
    previous_indexes: Dict[str, Dict[str, List[str]]],
) -> str:
    exact_sha_match = _resolve_index_lookup(
        previous_indexes["by_sha256"],
        file_hash,
        collision_label="sha256",
        previous_samples=previous_samples,
        relative_file_path=relative_file_path,
        file_hash=file_hash,
    )
    if exact_sha_match:
        return exact_sha_match

    legacy_hash_match = _resolve_index_lookup(
        previous_indexes["by_legacy_hash"],
        legacy_hash_12,
        collision_label="legacy_hash_12",
        previous_samples=previous_samples,
        relative_file_path=relative_file_path,
        file_hash=file_hash,
    )
    if legacy_hash_match:
        return legacy_hash_match

    previous_same_id = previous_samples.get(path_derived_id)
    if previous_same_id is not None:
        previous_sha = _entry_sha256(previous_same_id)
        previous_legacy_hash = _entry_legacy_hash(previous_same_id)
        if (
            (previous_sha and previous_sha != file_hash)
            or (previous_legacy_hash and previous_legacy_hash != legacy_hash_12)
        ):
            raise ValueError(
                f"Built-in sample '{path_derived_id}' changed content at "
                f"'{relative_file_path}'. Keep the old audio or mint a new identity."
            )
        return path_derived_id

    previous_same_path = _single_candidate(
        previous_indexes["by_path"],
        relative_file_path,
        collision_label="path",
    )
    if previous_same_path:
        previous_entry = previous_samples.get(previous_same_path, {})
        previous_sha = _entry_sha256(previous_entry)
        previous_legacy_hash = _entry_legacy_hash(previous_entry)
        if (
            (previous_sha and previous_sha != file_hash)
            or (previous_legacy_hash and previous_legacy_hash != legacy_hash_12)
        ):
            raise ValueError(
                f"Built-in sample path '{relative_file_path}' now points to different "
                f"audio than shipped id '{previous_same_path}'. Keep the old file or "
                "allow the old id to be removed explicitly."
            )
        return previous_same_path

    return path_derived_id


def validate_samples_manifest(
    samples_data: Dict[str, Any],
    *,
    samples_dir: str = "samples",
    previous_manifest: Optional[Dict[str, Any]] = None,
    allowed_removed_ids: Optional[Set[str]] = None,
) -> None:
    samples = _manifest_samples(samples_data)
    previous_samples = _manifest_samples(previous_manifest or {})
    allowed_removed_ids = allowed_removed_ids or set()
    samples_dir_path = Path(samples_dir)
    workspace_root = samples_dir_path.parent if samples_dir_path.parent != Path("") else Path(".")

    errors: List[str] = []
    alias_owners: Dict[str, str] = {}

    for sample_id, entry in samples.items():
        sample_path = _entry_path(entry)
        if not sample_path:
            errors.append(f"{sample_id}: missing path")
        else:
            path_obj = Path(sample_path)
            if not path_obj.is_absolute():
                path_obj = workspace_root / path_obj
            if not path_obj.exists():
                errors.append(f"{sample_id}: path does not exist: {sample_path}")

        asset_key = entry.get("asset_key")
        if asset_key is not None:
            if not isinstance(asset_key, str) or not asset_key.strip():
                errors.append(f"{sample_id}: asset_key must be a non-empty string")
            elif not asset_key.startswith("samples/"):
                errors.append(f"{sample_id}: asset_key must start with samples/: {asset_key}")

        for alias in [sample_id, _entry_legacy_hash(entry), *_entry_id_list(entry, "aliases"), *_entry_id_list(entry, "legacy_ids")]:
            if not alias:
                continue
            owner = alias_owners.get(alias)
            if owner and owner != sample_id:
                errors.append(
                    f"Alias/id '{alias}' is claimed by both '{owner}' and '{sample_id}'."
                )
            else:
                alias_owners[alias] = sample_id

    missing_previous_ids = sorted(
        sample_id
        for sample_id in previous_samples.keys()
        if sample_id not in samples and sample_id not in allowed_removed_ids
    )
    if missing_previous_ids:
        errors.append(
            "Previously shipped canonical ids disappeared: " + ", ".join(missing_previous_ids)
        )

    if errors:
        raise ValueError("Manifest validation failed:\n- " + "\n- ".join(errors))


def scan_samples_directory(
    samples_dir: str = "samples",
    *,
    previous_manifest_path: Optional[str] = None,
    allowed_removed_ids: Optional[Set[str]] = None,
) -> Dict[str, Any]:
    """Scan the samples directory and generate stable ids + compatibility aliases."""
    samples_dir_path = Path(samples_dir)

    if not samples_dir_path.exists():
        print(f"Samples directory '{samples_dir}' not found!")
        return {}

    previous_manifest = (
        _load_manifest(Path(previous_manifest_path)) if previous_manifest_path else {}
    )
    previous_samples = _manifest_samples(previous_manifest)
    workspace_root = _workspace_root_for_samples(samples_dir_path)
    previous_indexes = _previous_indexes(previous_samples, workspace_root)

    samples_data = {
        "schema_version": 4,
        "scan_timestamp": int(time.time()),
        "total_files": 0,
        "samples": {},
    }

    print(f"Scanning samples directory: {samples_dir_path.absolute()}")

    for root, _, files in os.walk(samples_dir_path):
        root_path = Path(root)
        audio_files = sorted(
            filename
            for filename in files
            if Path(filename).suffix.lower() in AUDIO_EXTENSIONS
        )
        if not audio_files:
            continue

        for filename in audio_files:
            file_path = root_path / filename
            print(f"  Hashing: {filename}...")

            file_hash = generate_file_hash(file_path)
            if not file_hash:
                continue

            path_derived_id = _stable_builtin_id(samples_dir_path, file_path)
            legacy_hash_12 = file_hash[:12]
            relative_file_path = _manifest_relative_path(samples_dir_path, file_path)
            asset_key = _safe_asset_key_from_path(relative_file_path)
            display_name = _display_name_from_file(file_path)
            display_path = _display_path_from_file(samples_dir_path, file_path)
            source_file_name = file_path.name

            canonical_id = _choose_canonical_id(
                path_derived_id=path_derived_id,
                relative_file_path=relative_file_path,
                file_hash=file_hash,
                legacy_hash_12=legacy_hash_12,
                previous_samples=previous_samples,
                previous_indexes=previous_indexes,
            )
            previous_entry = previous_samples.get(canonical_id, {})

            aliases = _sorted_unique_strings(
                [
                    legacy_hash_12,
                    path_derived_id if path_derived_id != canonical_id else "",
                    *_entry_id_list(previous_entry, "aliases"),
                ]
            )
            legacy_ids = _entry_id_list(previous_entry, "legacy_ids")

            sample_entry: Dict[str, Any] = {
                "path": relative_file_path,
                "asset_key": asset_key,
                "built_in": True,
                "sha256": file_hash,
                "legacy_hash_12": legacy_hash_12,
                "aliases": aliases,
                "display_name": display_name,
                "display_path": display_path,
                "source_file_name": source_file_name,
            }
            if legacy_ids:
                sample_entry["legacy_ids"] = legacy_ids

            if canonical_id in samples_data["samples"]:
                raise ValueError(
                    f"Multiple current files resolved to canonical id '{canonical_id}'. "
                    "Remove duplicates or keep only one shipped identity."
                )

            samples_data["samples"][canonical_id] = sample_entry
            samples_data["total_files"] += 1

    allowed_stale = _allowed_removals_when_previous_file_gone(
        previous_samples,
        workspace_root,
        set(samples_data["samples"].keys()),
    )
    allowed_removed_merged = set(allowed_removed_ids or set()) | allowed_stale

    validate_samples_manifest(
        samples_data,
        samples_dir=samples_dir,
        previous_manifest=previous_manifest,
        allowed_removed_ids=allowed_removed_merged,
    )

    print(f"Scan complete! Found {samples_data['total_files']} audio files.")
    return samples_data


def save_samples_manifest(
    samples_data: Dict[str, Any], output_file: str = "samples_manifest.json"
) -> None:
    """Save the samples data to a JSON file."""
    try:
        with open(output_file, "w", encoding="utf-8") as file_obj:
            json.dump(samples_data, file_obj, indent=2)
            file_obj.write("\n")
        print(f"Samples manifest saved to: {output_file}")
    except Exception as exc:
        print(f"Error saving manifest: {exc}")


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples-dir", default="samples")
    parser.add_argument("--output-file", default="samples_manifest.json")
    parser.add_argument(
        "--previous-manifest",
        default=None,
        help="Manifest to merge against. Defaults to the output file if it exists.",
    )
    parser.add_argument(
        "--allow-removed-id",
        action="append",
        default=[],
        help="Previously shipped canonical id allowed to disappear in this run.",
    )
    return parser


if __name__ == "__main__":
    arguments = _build_arg_parser().parse_args()
    previous_manifest_path = arguments.previous_manifest
    if previous_manifest_path is None and Path(arguments.output_file).exists():
        previous_manifest_path = arguments.output_file

    try:
        samples_data = scan_samples_directory(
            arguments.samples_dir,
            previous_manifest_path=previous_manifest_path,
            allowed_removed_ids=set(arguments.allow_removed_id),
        )
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    if samples_data:
        save_samples_manifest(samples_data, arguments.output_file)
