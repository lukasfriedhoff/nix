#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("repair-bridge-displaynames.py")
SPEC = importlib.util.spec_from_file_location("repair_bridge_displaynames", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RepairBridgeDisplayNamesTest(unittest.TestCase):
    def test_normalize_localpart(self):
        self.assertEqual(
            MODULE.normalize_user_id("whatsapp_49123", "h4xx.io"),
            "@whatsapp_49123:h4xx.io",
        )

    def test_preserve_full_user_id(self):
        self.assertEqual(
            MODULE.normalize_user_id("@telegram_42:h4xx.io", "ignored.example"),
            "@telegram_42:h4xx.io",
        )

    def test_raw_bridge_names_are_unresolved(self):
        for user_id in (
            "@whatsapp_49123:h4xx.io",
            "@whatsapp_lid-123:h4xx.io",
            "@signalprivate_27c919a7-221f-49dc-b626-595d7f924192:h4xx.io",
            "@telegram_42:h4xx.io",
        ):
            with self.subTest(user_id=user_id):
                self.assertTrue(
                    MODULE.unresolved_displayname(
                        MODULE.localpart(user_id),
                        user_id,
                    )
                )

    def test_phone_placeholder_is_unresolved(self):
        for displayname in (
            "+491739804698 (WA)",
            "+49 1512 3441897 (Signal Private)",
        ):
            with self.subTest(displayname=displayname):
                self.assertTrue(
                    MODULE.unresolved_displayname(
                        displayname,
                        "@whatsapp_491739804698:h4xx.io",
                    )
                )

    def test_human_name_with_digits_is_resolved(self):
        self.assertFalse(
            MODULE.unresolved_displayname(
                "Studio 54",
                "@signalprivate_27c919a7-221f-49dc-b626-595d7f924192:h4xx.io",
            )
        )

    def test_human_name_is_resolved(self):
        self.assertFalse(
            MODULE.unresolved_displayname(
                "Monika Klar (WA)",
                "@whatsapp_491739804698:h4xx.io",
            )
        )

    def test_load_mapping_rejects_conflicts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mapping.tsv"
            path.write_text("telegram_42|Alice\ntelegram_42|Bob\n")
            with self.assertRaisesRegex(ValueError, "conflicting names"):
                MODULE.load_mapping(path, "h4xx.io")


if __name__ == "__main__":
    unittest.main()
