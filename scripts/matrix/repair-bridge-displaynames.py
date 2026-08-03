#!/usr/bin/env python3

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


PHONE_DISPLAYNAME = re.compile(r"^\+?[0-9][0-9 -]*(?: \([^)]+\))?$")
RAW_LOCALPART = re.compile(
    r"^(?:whatsapp_(?:lid-)?[0-9]+|signalprivate_[0-9a-f-]+|telegram_[0-9]+)$"
)


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Repair unresolved Matrix bridge display names without renaming rooms."
        )
    )
    parser.add_argument("action", choices=("inventory", "repair"))
    parser.add_argument(
        "--mapping",
        required=True,
        type=Path,
        help=(
            "Pipe-delimited user-to-name file: "
            "<localpart or full Matrix user ID>|<display name>"
        ),
    )
    parser.add_argument(
        "--registration",
        required=True,
        type=Path,
        help="Bridge appservice registration containing its as_token",
    )
    parser.add_argument(
        "--homeserver-url",
        default="http://127.0.0.1:8008",
        help="Synapse client API base URL",
    )
    parser.add_argument("--server-name", default="h4xx.io")
    return parser.parse_args()


def normalize_user_id(value, server_name):
    value = value.strip()
    if value.startswith("@"):
        if ":" not in value:
            raise ValueError(f"full Matrix user ID lacks a server name: {value!r}")
        return value
    if not value or ":" in value:
        raise ValueError(f"invalid Matrix localpart: {value!r}")
    return f"@{value}:{server_name}"


def load_mapping(path, server_name):
    mapping = {}
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            raw_user_id, name = line.split("|", 1)
        except ValueError as error:
            raise ValueError(
                f"{path}:{line_number}: expected <user ID>|<display name>"
            ) from error
        user_id = normalize_user_id(raw_user_id, server_name)
        name = name.strip()
        if not name:
            raise ValueError(f"{path}:{line_number}: display name must not be empty")
        if user_id in mapping and mapping[user_id] != name:
            raise ValueError(
                f"{path}:{line_number}: conflicting names for {user_id}: "
                f"{mapping[user_id]!r} and {name!r}"
            )
        mapping[user_id] = name
    return mapping


class MatrixClient:
    def __init__(self, base_url, access_token):
        self.base_url = base_url.rstrip("/")
        self.access_token = access_token

    def request(self, method, path, acting_user=None, body=None):
        query = ""
        if acting_user:
            query = "?" + urllib.parse.urlencode({"user_id": acting_user})
        request = urllib.request.Request(
            f"{self.base_url}{path}{query}",
            data=None if body is None else json.dumps(body).encode(),
            method=method,
            headers={
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(
                f"{method} {path} failed with HTTP {error.code}: {detail}"
            ) from error
        if not payload:
            return {}
        return json.loads(payload)


def encoded(value):
    return urllib.parse.quote(value, safe="")


def localpart(user_id):
    return user_id[1:].split(":", 1)[0]


def unresolved_displayname(displayname, user_id):
    if not displayname:
        return True
    user_localpart = localpart(user_id)
    normalized = displayname.removeprefix("@").split(":", 1)[0]
    return (
        normalized == user_localpart
        or RAW_LOCALPART.fullmatch(normalized) is not None
        or PHONE_DISPLAYNAME.fullmatch(displayname) is not None
    )


def load_appservice_token(path):
    for raw_line in path.read_text().splitlines():
        key, separator, value = raw_line.partition(":")
        if separator and key.strip() == "as_token":
            token = value.strip().strip("'\"")
            if token:
                return token
    raise ValueError(f"{path}: missing non-empty as_token")


def main():
    args = parse_args()
    mapping = load_mapping(args.mapping, args.server_name)
    client = MatrixClient(
        args.homeserver_url,
        load_appservice_token(args.registration),
    )
    changed_profiles = 0
    changed_memberships = 0
    skipped_resolved = 0
    missing_profiles = 0
    errors = 0

    for user_id, wanted_name in sorted(mapping.items()):
        try:
            profile = client.request(
                "GET",
                f"/_matrix/client/v3/profile/{encoded(user_id)}",
                acting_user=user_id,
            )
        except RuntimeError as error:
            if "HTTP 404:" in str(error):
                missing_profiles += 1
                continue
            print(f"ERROR profile {user_id}: {error}", file=sys.stderr)
            errors += 1
            continue

        current_name = profile.get("displayname", "")
        profile_needs_update = (
            current_name != wanted_name
            and unresolved_displayname(current_name, user_id)
        )
        if current_name != wanted_name and not profile_needs_update:
            skipped_resolved += 1
            continue

        try:
            joined_rooms = client.request(
                "GET",
                "/_matrix/client/v3/joined_rooms",
                acting_user=user_id,
            ).get("joined_rooms", [])
        except RuntimeError as error:
            print(f"ERROR rooms {user_id}: {error}", file=sys.stderr)
            errors += 1
            continue

        room_updates = []
        for room_id in joined_rooms:
            try:
                membership = client.request(
                    "GET",
                    (
                        f"/_matrix/client/v3/rooms/{encoded(room_id)}"
                        f"/state/m.room.member/{encoded(user_id)}"
                    ),
                    acting_user=user_id,
                )
            except RuntimeError as error:
                print(
                    f"ERROR membership {user_id} in {room_id}: {error}",
                    file=sys.stderr,
                )
                errors += 1
                continue
            if membership.get("membership") != "join":
                continue
            if membership.get("displayname") == wanted_name:
                continue
            room_updates.append((room_id, membership))

        if profile_needs_update or room_updates:
            print(
                json.dumps(
                    {
                        "user_id": user_id,
                        "current_displayname": current_name,
                        "desired_displayname": wanted_name,
                        "joined_rooms": len(joined_rooms),
                        "profile_update": profile_needs_update,
                        "membership_updates": len(room_updates),
                        "action": args.action,
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )

        if args.action != "repair":
            continue

        if profile_needs_update:
            try:
                client.request(
                    "PUT",
                    f"/_matrix/client/v3/profile/{encoded(user_id)}/displayname",
                    acting_user=user_id,
                    body={"displayname": wanted_name},
                )
                changed_profiles += 1
            except RuntimeError as error:
                print(f"ERROR update profile {user_id}: {error}", file=sys.stderr)
                errors += 1
                continue

        for room_id, membership in room_updates:
            membership["displayname"] = wanted_name
            try:
                client.request(
                    "PUT",
                    (
                        f"/_matrix/client/v3/rooms/{encoded(room_id)}"
                        f"/state/m.room.member/{encoded(user_id)}"
                    ),
                    acting_user=user_id,
                    body=membership,
                )
                changed_memberships += 1
            except RuntimeError as error:
                print(
                    f"ERROR update membership {user_id} in {room_id}: {error}",
                    file=sys.stderr,
                )
                errors += 1

    print(
        json.dumps(
            {
                "changed_profiles": changed_profiles,
                "changed_memberships": changed_memberships,
                "errors": errors,
                "mapped_users": len(mapping),
                "missing_profiles": missing_profiles,
                "skipped_resolved_profiles": skipped_resolved,
            },
            sort_keys=True,
        )
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
