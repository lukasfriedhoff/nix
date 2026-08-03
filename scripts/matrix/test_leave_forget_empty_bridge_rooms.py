#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("leave-forget-empty-bridge-rooms.py")
SPEC = importlib.util.spec_from_file_location(
    "leave_forget_empty_bridge_rooms",
    SCRIPT,
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeClient:
    def __init__(self, membership="join", state=None, pages=None):
        self.membership = membership
        self.state = state or []
        self.pages = pages or [{"chunk": []}]
        self.page_index = 0

    def request(self, method, path, body=None):
        if "/state/m.room.member/" in path:
            return {"membership": self.membership}
        if path.endswith("/state"):
            return self.state
        if "/messages?" in path:
            page = self.pages[min(self.page_index, len(self.pages) - 1)]
            self.page_index += 1
            return page
        raise AssertionError(f"unexpected request: {method} {path} {body}")


def signal_state():
    return [
        {
            "type": "m.room.member",
            "state_key": (
                "@signalprivate_27c919a7-221f-49dc-b626-595d7f924192:"
                "m.h4.ddnss.org"
            ),
            "content": {"membership": "join"},
        }
    ]


class EmptyBridgeRoomTest(unittest.TestCase):
    def inspect(self, client, room_id="!room:m.h4.ddnss.org"):
        return MODULE.inspect_room(
            client,
            room_id,
            "@lukasf:h4xx.io",
            "m.h4.ddnss.org",
            "signalprivate_",
            100,
            10,
        )

    def test_state_only_legacy_signal_room_is_safe(self):
        result = self.inspect(FakeClient(state=signal_state()))
        self.assertTrue(result["safe"])
        self.assertEqual(result["timeline_events"], 0)

    def test_timeline_event_blocks_cleanup(self):
        result = self.inspect(
            FakeClient(
                state=signal_state(),
                pages=[
                    {
                        "chunk": [
                            {
                                "event_id": "$message",
                                "type": "m.room.encrypted",
                                "content": {},
                            }
                        ]
                    }
                ],
            )
        )
        self.assertFalse(result["safe"])
        self.assertEqual(result["reason"], "contains-timeline-events")

    def test_state_events_do_not_block_cleanup(self):
        result = self.inspect(
            FakeClient(
                state=signal_state(),
                pages=[
                    {
                        "chunk": [
                            {
                                "event_id": "$member",
                                "type": "m.room.member",
                                "state_key": "@someone:example.test",
                                "content": {"membership": "join"},
                            }
                        ],
                        "end": "next",
                    },
                    {"chunk": []},
                ],
            )
        )
        self.assertTrue(result["safe"])

    def test_missing_signal_ghost_blocks_cleanup(self):
        result = self.inspect(FakeClient())
        self.assertFalse(result["safe"])
        self.assertEqual(result["reason"], "no-joined-legacy-ghost")

    def test_wrong_room_server_blocks_cleanup(self):
        result = self.inspect(
            FakeClient(state=signal_state()),
            room_id="!room:h4xx.io",
        )
        self.assertFalse(result["safe"])
        self.assertEqual(result["reason"], "wrong-room-server")


if __name__ == "__main__":
    unittest.main()
