#!/usr/bin/env python3

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Leave and forget verified empty legacy Matrix bridge rooms "
            "without renaming or purging them."
        )
    )
    parser.add_argument("action", choices=("inventory", "cleanup"))
    parser.add_argument("--rooms", required=True, type=Path)
    parser.add_argument("--token-file", required=True, type=Path)
    parser.add_argument("--user-id", required=True)
    parser.add_argument("--legacy-server-name", required=True)
    parser.add_argument("--bridge-localpart-prefix", required=True)
    parser.add_argument(
        "--homeserver-url",
        default="https://matrix.h4xx.io",
        help="Matrix client API base URL",
    )
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument("--max-pages", type=int, default=100)
    return parser.parse_args()


def encoded(value):
    return urllib.parse.quote(value, safe="")


def load_nonempty_lines(path):
    values = []
    seen = set()
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        value = raw_line.strip()
        if not value or value.startswith("#"):
            continue
        if value in seen:
            raise ValueError(f"{path}:{line_number}: duplicate value: {value}")
        values.append(value)
        seen.add(value)
    return values


class MatrixRequestError(RuntimeError):
    def __init__(self, method, path, status, detail):
        super().__init__(f"{method} {path} failed with HTTP {status}: {detail}")
        self.status = status


class MatrixClient:
    def __init__(self, base_url, access_token):
        self.base_url = base_url.rstrip("/")
        self.access_token = access_token

    def request(self, method, path, body=None):
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=None if body is None else json.dumps(body).encode(),
            method=method,
            headers={
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json",
            },
        )
        for attempt in range(6):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    payload = response.read()
                return {} if not payload else json.loads(payload)
            except urllib.error.HTTPError as error:
                detail = error.read().decode(errors="replace")
                if error.code == 429 and attempt < 5:
                    try:
                        retry = json.loads(detail).get("retry_after_ms", 1000) / 1000
                    except json.JSONDecodeError:
                        retry = 1
                    time.sleep(max(retry, 0.1))
                    continue
                raise MatrixRequestError(
                    method,
                    path,
                    error.code,
                    detail,
                ) from error


def expected_room_suffix(legacy_server_name):
    return f":{legacy_server_name}"


def expected_ghost_prefix(bridge_localpart_prefix):
    return f"@{bridge_localpart_prefix}"


def joined_legacy_ghosts(
    state,
    legacy_server_name,
    bridge_localpart_prefix,
):
    suffix = expected_room_suffix(legacy_server_name)
    prefix = expected_ghost_prefix(bridge_localpart_prefix)
    ghosts = []
    for event in state:
        if event.get("type") != "m.room.member":
            continue
        user_id = event.get("state_key", "")
        if not user_id.startswith(prefix) or not user_id.endswith(suffix):
            continue
        if event.get("content", {}).get("membership") == "join":
            ghosts.append(user_id)
    return ghosts


def count_timeline_events(client, room_id, page_size, max_pages):
    from_token = None
    timeline_events = 0
    pages = 0

    while pages < max_pages:
        query = {"dir": "b", "limit": str(page_size)}
        if from_token:
            query["from"] = from_token
        path = (
            f"/_matrix/client/v3/rooms/{encoded(room_id)}/messages?"
            f"{urllib.parse.urlencode(query)}"
        )
        response = client.request("GET", path)
        pages += 1
        chunk = response.get("chunk", [])
        timeline_events += sum("state_key" not in event for event in chunk)
        if timeline_events:
            return timeline_events, pages, True

        next_token = response.get("end")
        if not chunk or not next_token or next_token == from_token:
            return 0, pages, True
        from_token = next_token

    return 0, pages, False


def inspect_room(
    client,
    room_id,
    user_id,
    legacy_server_name,
    bridge_localpart_prefix,
    page_size,
    max_pages,
):
    result = {
        "room_id": room_id,
        "safe": False,
        "reason": None,
        "membership": None,
        "legacy_ghosts": [],
        "timeline_events": None,
        "history_complete": False,
    }
    if not room_id.endswith(expected_room_suffix(legacy_server_name)):
        result["reason"] = "wrong-room-server"
        return result

    membership_path = (
        f"/_matrix/client/v3/rooms/{encoded(room_id)}"
        f"/state/m.room.member/{encoded(user_id)}"
    )
    try:
        membership = client.request("GET", membership_path)
    except MatrixRequestError as error:
        if error.status in (403, 404):
            result["reason"] = "not-accessible"
            return result
        raise

    result["membership"] = membership.get("membership")
    if result["membership"] != "join":
        result["reason"] = "not-joined"
        return result

    state = client.request(
        "GET",
        f"/_matrix/client/v3/rooms/{encoded(room_id)}/state",
    )
    ghosts = joined_legacy_ghosts(
        state,
        legacy_server_name,
        bridge_localpart_prefix,
    )
    result["legacy_ghosts"] = ghosts
    if not ghosts:
        result["reason"] = "no-joined-legacy-ghost"
        return result

    timeline_events, pages, complete = count_timeline_events(
        client,
        room_id,
        page_size,
        max_pages,
    )
    result["timeline_events"] = timeline_events
    result["history_pages"] = pages
    result["history_complete"] = complete
    if not complete:
        result["reason"] = "history-page-limit"
        return result
    if timeline_events:
        result["reason"] = "contains-timeline-events"
        return result

    result["safe"] = True
    result["reason"] = "verified-empty-legacy-bridge-room"
    return result


def main():
    args = parse_args()
    token = args.token_file.read_text().strip()
    if not token:
        raise ValueError(f"{args.token_file}: access token must not be empty")
    room_ids = load_nonempty_lines(args.rooms)
    client = MatrixClient(args.homeserver_url, token)
    summary = {
        "action": args.action,
        "rooms": len(room_ids),
        "safe": 0,
        "blocked": 0,
        "left": 0,
        "forgotten": 0,
        "errors": 0,
    }

    for room_id in room_ids:
        try:
            result = inspect_room(
                client,
                room_id,
                args.user_id,
                args.legacy_server_name,
                args.bridge_localpart_prefix,
                args.page_size,
                args.max_pages,
            )
            print(json.dumps(result, sort_keys=True))
            if not result["safe"]:
                summary["blocked"] += 1
                continue
            summary["safe"] += 1
            if args.action != "cleanup":
                continue

            client.request(
                "POST",
                f"/_matrix/client/v3/rooms/{encoded(room_id)}/leave",
                body={},
            )
            summary["left"] += 1
            client.request(
                "POST",
                f"/_matrix/client/v3/rooms/{encoded(room_id)}/forget",
                body={},
            )
            summary["forgotten"] += 1
        except (MatrixRequestError, ValueError) as error:
            summary["errors"] += 1
            print(f"ERROR {room_id}: {error}", file=sys.stderr)

    print(json.dumps({"summary": summary}, sort_keys=True))
    return 1 if summary["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
