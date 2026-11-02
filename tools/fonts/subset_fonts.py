#!/usr/bin/env python3
"""
ReturnFare W7-C Font Subsetting Script.

Subsets verified original source TTF fonts into optimized WOFF2 web fonts
using the collected UTF-8 character corpus:
1. LXGW WenKai TC Regular (https://github.com/lxgw/LxgwWenkaiTC/releases/download/v1.530/LXGWWenKaiTC-Regular.ttf)
2. Taipei Sans TC Beta Regular (https://drive.usercontent.google.com/download?id=1eGAsTN1HBpJAkeVM57_C7ccp7hbgSz3_&export=download&confirm=t)

Safety & Atomicity:
- Generates candidate WOFF2 files in temporary storage using subset.save_font to enforce true WOFF2 format.
- Reloads each candidate WOFF2 and verifies both WOFF2 magic header (b'wOF2') + flavor=='woff2' and complete cmap coverage.
- Uses paired rollback: if second file replacement fails, first file is rolled back from backup to preserve prior deployment byte-identically.
- Emits detailed before/after size, SHA256, and missing glyph metrics to _qa/fonts/report.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from fontTools import subset, ttLib

# Verified original source specifications
WENKAI_SOURCE_SHA256 = "6662480A3F95B4A90C80B189C679617A48ADCE3A505118A6AF63CE5A482B83FA"
WENKAI_SOURCE_SIZE = 15341148
WENKAI_SOURCE_URL = "https://github.com/lxgw/LxgwWenkaiTC/releases/download/v1.530/LXGWWenKaiTC-Regular.ttf"

TAIPEI_SOURCE_SHA256 = "8CC967E1E428C552701C461E8169E6AE76C7A23694EA1A6A786D6746ADEC53C4"
TAIPEI_SOURCE_SIZE = 20659344
TAIPEI_SOURCE_URL = "https://drive.usercontent.google.com/download?id=1eGAsTN1HBpJAkeVM57_C7ccp7hbgSz3_&export=download&confirm=t"


def compute_sha256(file_path: Path) -> str:
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().upper()


def get_file_info(file_path: Path) -> Dict[str, Any]:
    if not file_path.exists():
        return {"exists": False, "size": 0, "sha256": None}
    return {
        "exists": True,
        "size": file_path.stat().st_size,
        "sha256": compute_sha256(file_path),
    }


def validate_source_font(
    source_path: Path,
    expected_sha256: str,
    expected_size: int,
    font_name: str,
    official_url: str,
    validate_hash: bool = True,
) -> None:
    if not source_path.exists():
        raise FileNotFoundError(
            f"Source font for {font_name} not found at {source_path}.\n"
            f"Please obtain the verified original TTF from:\n"
            f"  {official_url}\n"
            f"and place it at:\n"
            f"  {source_path}\n"
            f"Expected SHA256: {expected_sha256}\n"
            f"Expected Size: {expected_size} bytes."
        )

    if not validate_hash:
        return

    actual_size = source_path.stat().st_size
    actual_sha256 = compute_sha256(source_path)

    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"Source font {font_name} at {source_path} has hash mismatch:\n"
            f"  Expected: {expected_sha256} ({expected_size} bytes)\n"
            f"  Actual:   {actual_sha256} ({actual_size} bytes)\n"
            "This input may be an already-subsetted output or corrupted file.\n"
            "Aborting subsetting to protect font quality."
        )


def subset_ttf_to_woff2(
    source_ttf: Path,
    target_temp_woff2: Path,
    corpus_text: str,
) -> Tuple[float, int]:
    """Subset TTF source to WOFF2 using fontTools. Returns (duration_sec, output_bytes)."""
    t0 = time.time()
    options = subset.Options()
    options.flavor = "woff2"
    # Preserve name IDs 0 (copyright), 13 (license description), 14 (license URL)
    options.name_IDs = list(set(options.name_IDs) | {0, 13, 14})
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=corpus_text)

    font = subset.load_font(str(source_ttf), options)
    try:
        subsetter.subset(font)
        target_temp_woff2.parent.mkdir(parents=True, exist_ok=True)
        # subset.save_font correctly sets font.flavor='woff2' and compiles WOFF2 SFNT
        subset.save_font(font, str(target_temp_woff2), options)
    finally:
        font.close()

    dur = time.time() - t0
    size = target_temp_woff2.stat().st_size
    return dur, size


def verify_woff2_format_and_coverage(
    woff2_path: Path,
    required_chars: List[str],
) -> List[str]:
    """
    Verify that file has valid WOFF2 header magic (b'wOF2'), flavor=='woff2',
    and that every required character is mapped in cmap.
    """
    with open(woff2_path, "rb") as f:
        magic = f.read(4)
    if magic != b"wOF2":
        raise ValueError(
            f"File {woff2_path} is not valid WOFF2 format! Header magic is {magic!r}, expected b'wOF2'."
        )

    font = ttLib.TTFont(str(woff2_path))
    try:
        if font.flavor != "woff2":
            raise ValueError(
                f"File {woff2_path} TTFont.flavor is {font.flavor!r}, expected 'woff2'."
            )
        cmap = font.getBestCmap()
        if cmap is None:
            raise ValueError(f"No usable cmap found in WOFF2 font {woff2_path}")
        missing = [c for c in required_chars if ord(c) not in cmap]
        return missing
    finally:
        font.close()


def run_subsetting(
    project_root: Path,
    corpus_path: Optional[Path] = None,
    source_wenkai: Optional[Path] = None,
    source_taipei: Optional[Path] = None,
    dest_wenkai: Optional[Path] = None,
    dest_taipei: Optional[Path] = None,
    report_path: Optional[Path] = None,
    _validate_hashes: bool = True,
) -> Dict[str, Any]:
    corpus_file = corpus_path or (project_root / "_qa" / "fonts" / "corpus.txt")
    src_wenkai = source_wenkai or (project_root / "_qa" / "fonts" / "source" / "LXGWWenKaiTC-Regular.ttf")
    src_taipei = source_taipei or (project_root / "_qa" / "fonts" / "source" / "TaipeiSansTCBeta-Regular.ttf")
    dst_wenkai = dest_wenkai or (project_root / "web" / "public" / "fonts" / "lxgw-wenkai-tc.woff2")
    dst_taipei = dest_taipei or (project_root / "web" / "public" / "fonts" / "taipei-sans-tc.woff2")
    rep_file = report_path or (project_root / "_qa" / "fonts" / "report.json")

    # 1. Read and validate corpus
    if not corpus_file.exists():
        raise FileNotFoundError(
            f"Corpus file not found: {corpus_file}.\n"
            "Please run 'npm run fonts:collect' first to generate corpus."
        )

    with open(corpus_file, "r", encoding="utf-8") as f:
        corpus_text = f.read()

    required_chars = list(corpus_text)
    if not required_chars:
        raise ValueError(f"Corpus file {corpus_file} is empty.")

    # 2. Validate source fonts (must be original un-subsetted TTF)
    validate_source_font(
        src_wenkai,
        WENKAI_SOURCE_SHA256,
        WENKAI_SOURCE_SIZE,
        "LXGW WenKai TC Regular",
        WENKAI_SOURCE_URL,
        validate_hash=_validate_hashes,
    )
    validate_source_font(
        src_taipei,
        TAIPEI_SOURCE_SHA256,
        TAIPEI_SOURCE_SIZE,
        "Taipei Sans TC Beta Regular",
        TAIPEI_SOURCE_URL,
        validate_hash=_validate_hashes,
    )

    # Record "before" status of deployed files
    before_wenkai = get_file_info(dst_wenkai)
    before_taipei = get_file_info(dst_taipei)

    # 3. Create candidate temporary WOFF2 files
    temp_dir = Path(tempfile.mkdtemp(prefix="rf_subset_", dir=str(project_root / "_qa" / "fonts")))
    cand_wenkai = temp_dir / "candidate_wenkai.woff2"
    cand_taipei = temp_dir / "candidate_taipei.woff2"

    try:
        # Subset font 1 (WenKai)
        t_wenkai, size_wenkai = subset_ttf_to_woff2(src_wenkai, cand_wenkai, corpus_text)
        missing_wenkai = verify_woff2_format_and_coverage(cand_wenkai, required_chars)
        if missing_wenkai:
            samples = [f"{c} (U+{ord(c):04X})" for c in missing_wenkai[:10]]
            raise ValueError(
                f"WenKai subset candidate is missing {len(missing_wenkai)} required characters: {samples}. "
                "Aborting replacement."
            )

        # Subset font 2 (Taipei)
        t_taipei, size_taipei = subset_ttf_to_woff2(src_taipei, cand_taipei, corpus_text)
        missing_taipei = verify_woff2_format_and_coverage(cand_taipei, required_chars)
        if missing_taipei:
            samples = [f"{c} (U+{ord(c):04X})" for c in missing_taipei[:10]]
            raise ValueError(
                f"Taipei subset candidate is missing {len(missing_taipei)} required characters: {samples}. "
                "Aborting replacement."
            )

        # 4. Paired replacement with rollback protection
        backup_dir = temp_dir / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        bak_wenkai = backup_dir / "backup_wenkai.woff2"
        bak_taipei = backup_dir / "backup_taipei.woff2"

        wenkai_existed = dst_wenkai.exists()
        taipei_existed = dst_taipei.exists()

        if wenkai_existed:
            shutil.copy2(dst_wenkai, bak_wenkai)
        if taipei_existed:
            shutil.copy2(dst_taipei, bak_taipei)

        wenkai_replaced = False
        taipei_replaced = False

        try:
            dst_wenkai.parent.mkdir(parents=True, exist_ok=True)
            dst_taipei.parent.mkdir(parents=True, exist_ok=True)

            os.replace(str(cand_wenkai), str(dst_wenkai))
            wenkai_replaced = True

            os.replace(str(cand_taipei), str(dst_taipei))
            taipei_replaced = True
        except Exception as replace_err:
            # Roll back both files if second (or any) replacement fails
            if wenkai_replaced:
                if wenkai_existed:
                    shutil.copy2(bak_wenkai, dst_wenkai)
                else:
                    try:
                        dst_wenkai.unlink()
                    except OSError:
                        pass
            if taipei_replaced:
                if taipei_existed:
                    shutil.copy2(bak_taipei, dst_taipei)
                else:
                    try:
                        dst_taipei.unlink()
                    except OSError:
                        pass
            raise RuntimeError(
                f"Replacement failed ({replace_err}); rolled back both deployed fonts to original state."
            ) from replace_err

        # Record "after" status
        after_wenkai = get_file_info(dst_wenkai)
        after_taipei = get_file_info(dst_taipei)

        report_data = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "corpus": {
                "path": str(corpus_file),
                "totalRequiredCharacters": len(required_chars),
            },
            "fonts": {
                "lxgw_wenkai_tc": {
                    "source": {
                        "path": str(src_wenkai),
                        "sha256": compute_sha256(src_wenkai),
                        "size": src_wenkai.stat().st_size,
                        "officialUrl": WENKAI_SOURCE_URL,
                    },
                    "deployed": {
                        "path": str(dst_wenkai),
                        "before": before_wenkai,
                        "after": after_wenkai,
                    },
                    "missingCharactersCount": len(missing_wenkai),
                    "missingCharacters": missing_wenkai,
                    "subsetDurationSeconds": round(t_wenkai, 3),
                },
                "taipei_sans_tc": {
                    "source": {
                        "path": str(src_taipei),
                        "sha256": compute_sha256(src_taipei),
                        "size": src_taipei.stat().st_size,
                        "officialUrl": TAIPEI_SOURCE_URL,
                    },
                    "deployed": {
                        "path": str(dst_taipei),
                        "before": before_taipei,
                        "after": after_taipei,
                    },
                    "missingCharactersCount": len(missing_taipei),
                    "missingCharacters": missing_taipei,
                    "subsetDurationSeconds": round(t_taipei, 3),
                },
            },
            "status": "success",
            "reportPath": str(rep_file),
        }

        rep_file.parent.mkdir(parents=True, exist_ok=True)
        with open(rep_file, "w", encoding="utf-8") as f:
            json.dump(report_data, f, indent=2, ensure_ascii=False)

        return report_data

    finally:
        # Clean up temporary directory
        if temp_dir.exists():
            shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="ReturnFare Font Subsetting Utility")
    parser.add_argument("--corpus", type=Path, help="Path to corpus.txt")
    parser.add_argument("--source-wenkai", type=Path, help="Path to LXGWWenKaiTC TTF")
    parser.add_argument("--source-taipei", type=Path, help="Path to TaipeiSansTCBeta TTF")
    parser.add_argument("--dest-wenkai", type=Path, help="Destination path for WenKai WOFF2")
    parser.add_argument("--dest-taipei", type=Path, help="Destination path for Taipei WOFF2")
    parser.add_argument("--report", type=Path, help="Path for output report.json")

    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[2]

    try:
        report = run_subsetting(
            project_root=project_root,
            corpus_path=args.corpus,
            source_wenkai=args.source_wenkai,
            source_taipei=args.source_taipei,
            dest_wenkai=args.dest_wenkai,
            dest_taipei=args.dest_taipei,
            report_path=args.report,
        )
        print("[subset_fonts] Subsetting completed successfully!")
        wenkai_rep = report["fonts"]["lxgw_wenkai_tc"]
        taipei_rep = report["fonts"]["taipei_sans_tc"]
        print(f"  WenKai: {wenkai_rep['deployed']['before']['size']} -> {wenkai_rep['deployed']['after']['size']} bytes (missing: {wenkai_rep['missingCharactersCount']})")
        print(f"  Taipei: {taipei_rep['deployed']['before']['size']} -> {taipei_rep['deployed']['after']['size']} bytes (missing: {taipei_rep['missingCharactersCount']})")
        print(f"  Report written to: {report['reportPath']}")
    except Exception as e:
        print(f"[subset_fonts] Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
