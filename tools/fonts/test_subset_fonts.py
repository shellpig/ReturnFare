"""
Unit tests for ReturnFare Font Subsetting Utility (tools/fonts/subset_fonts.py).

Tests safety, atomicity with rollback, WOFF2 format verification, and error handling.
"""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fontTools import ttLib
from subset_fonts import (
    TAIPEI_SOURCE_SHA256,
    TAIPEI_SOURCE_SIZE,
    TAIPEI_SOURCE_URL,
    WENKAI_SOURCE_SHA256,
    WENKAI_SOURCE_SIZE,
    WENKAI_SOURCE_URL,
    run_subsetting,
    validate_source_font,
    verify_woff2_format_and_coverage,
)


class TestSubsetFonts(unittest.TestCase):
    def setUp(self) -> None:
        self.project_root = Path(__file__).resolve().parents[2]
        self.test_dir = Path(tempfile.mkdtemp(prefix="rf_font_test_"))
        self.corpus_file = self.test_dir / "corpus.txt"
        self.corpus_file.write_text("溫泉小鎮測試字元", encoding="utf-8")

        # Mock previous deployed outputs with distinct bytes
        self.dest_wenkai = self.test_dir / "lxgw-wenkai-tc.woff2"
        self.dest_taipei = self.test_dir / "taipei-sans-tc.woff2"
        self.dest_wenkai.write_bytes(b"MOCK_PREVIOUS_DEPLOYED_WENKAI_BYTES")
        self.dest_taipei.write_bytes(b"MOCK_PREVIOUS_DEPLOYED_TAIPEI_BYTES")

        self.report_file = self.test_dir / "report.json"

        self.real_wenkai_ttf = self.project_root / "_qa" / "fonts" / "source" / "LXGWWenKaiTC-Regular.ttf"
        self.real_taipei_ttf = self.project_root / "_qa" / "fonts" / "source" / "TaipeiSansTCBeta-Regular.ttf"

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_generation_failure_preserves_both_previous_outputs(self) -> None:
        """If font 2 fails during subsetting or coverage verification, neither deployed font is overwritten."""
        bad_taipei = self.test_dir / "bad_taipei.ttf"
        bad_taipei.write_bytes(b"NOT_A_VALID_TTF_FONT_FILE")

        with patch("subset_fonts.validate_source_font"):
            with self.assertRaises(Exception):
                run_subsetting(
                    project_root=self.project_root,
                    corpus_path=self.corpus_file,
                    source_wenkai=self.real_wenkai_ttf,
                    source_taipei=bad_taipei,
                    dest_wenkai=self.dest_wenkai,
                    dest_taipei=self.dest_taipei,
                    report_path=self.report_file,
                )

        # Both previous outputs MUST remain untouched
        self.assertEqual(
            self.dest_wenkai.read_bytes(),
            b"MOCK_PREVIOUS_DEPLOYED_WENKAI_BYTES",
            "WenKai deployed font was overwritten despite second font failure!",
        )
        self.assertEqual(
            self.dest_taipei.read_bytes(),
            b"MOCK_PREVIOUS_DEPLOYED_TAIPEI_BYTES",
            "Taipei deployed font was corrupted or overwritten!",
        )

    def test_second_replacement_failure_rolls_back_first_output(self) -> None:
        """If replacing the second deployed font fails, the first font is rolled back to original bytes."""
        original_replace = os.replace
        replace_count = 0

        def failing_second_replace(src: str, dst: str) -> None:
            nonlocal replace_count
            replace_count += 1
            if replace_count == 1:
                # First replacement (WenKai) succeeds
                original_replace(src, dst)
                return
            # Second replacement (Taipei) fails
            raise OSError("Injected second replacement I/O failure")

        with patch("os.replace", side_effect=failing_second_replace):
            with self.assertRaises(RuntimeError) as ctx:
                run_subsetting(
                    project_root=self.project_root,
                    corpus_path=self.corpus_file,
                    source_wenkai=self.real_wenkai_ttf,
                    source_taipei=self.real_taipei_ttf,
                    dest_wenkai=self.dest_wenkai,
                    dest_taipei=self.dest_taipei,
                    report_path=self.report_file,
                )
            self.assertIn("rolled back both deployed fonts", str(ctx.exception))

        # Both previous outputs MUST remain byte-identical to original state
        self.assertEqual(
            self.dest_wenkai.read_bytes(),
            b"MOCK_PREVIOUS_DEPLOYED_WENKAI_BYTES",
            "WenKai deployed font was not restored after second replacement failure!",
        )
        self.assertEqual(
            self.dest_taipei.read_bytes(),
            b"MOCK_PREVIOUS_DEPLOYED_TAIPEI_BYTES",
            "Taipei deployed font was corrupted!",
        )

    def test_output_is_real_woff2_with_magic_and_flavor(self) -> None:
        """Successful generation produces real WOFF2 files with b'wOF2' magic and flavor=='woff2'."""
        report = run_subsetting(
            project_root=self.project_root,
            corpus_path=self.corpus_file,
            source_wenkai=self.real_wenkai_ttf,
            source_taipei=self.real_taipei_ttf,
            dest_wenkai=self.dest_wenkai,
            dest_taipei=self.dest_taipei,
            report_path=self.report_file,
        )
        self.assertEqual(report["status"], "success")

        for font_path in [self.dest_wenkai, self.dest_taipei]:
            # 1. Header magic check
            with open(font_path, "rb") as f:
                magic = f.read(4)
            self.assertEqual(magic, b"wOF2", f"{font_path} does not have WOFF2 magic bytes!")

            # 2. TTFont flavor check
            font = ttLib.TTFont(str(font_path))
            try:
                self.assertEqual(font.flavor, "woff2", f"{font_path} flavor is {font.flavor}, expected 'woff2'")
            finally:
                font.close()

    def test_renamed_ttf_rejection(self) -> None:
        """A TTF file renamed to .woff2 must be rejected by verify_woff2_format_and_coverage."""
        renamed_ttf = self.test_dir / "fake.woff2"
        # Copy real TTF (header 00010000) to fake.woff2
        shutil.copy2(self.real_wenkai_ttf, renamed_ttf)

        with self.assertRaises(ValueError) as ctx:
            verify_woff2_format_and_coverage(renamed_ttf, ["溫"])
        self.assertIn("not valid WOFF2 format", str(ctx.exception))

    def test_missing_source_fails_with_instruction(self) -> None:
        """Missing source TTF raises FileNotFoundError with download URL and setup instruction."""
        missing_path = self.test_dir / "nonexistent.ttf"
        with self.assertRaises(FileNotFoundError) as ctx:
            validate_source_font(
                source_path=missing_path,
                expected_sha256=WENKAI_SOURCE_SHA256,
                expected_size=WENKAI_SOURCE_SIZE,
                font_name="LXGW WenKai TC Regular",
                official_url=WENKAI_SOURCE_URL,
            )
        err_msg = str(ctx.exception)
        self.assertIn(WENKAI_SOURCE_URL, err_msg)
        self.assertIn(WENKAI_SOURCE_SHA256, err_msg)

    def test_source_hash_mismatch_prevents_subsetting(self) -> None:
        """Hash mismatch aborts execution to prevent subsetting already subsetted or corrupt fonts."""
        mismatched_ttf = self.test_dir / "mismatched.ttf"
        mismatched_ttf.write_bytes(b"SOME_MODIFIED_DATA")

        with self.assertRaises(ValueError) as ctx:
            validate_source_font(
                source_path=mismatched_ttf,
                expected_sha256=TAIPEI_SOURCE_SHA256,
                expected_size=TAIPEI_SOURCE_SIZE,
                font_name="Taipei Sans TC Beta Regular",
                official_url=TAIPEI_SOURCE_URL,
            )
        self.assertIn("hash mismatch", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
