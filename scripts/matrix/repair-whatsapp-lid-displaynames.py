#!/usr/bin/env python3

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Repair unresolved migrated WhatsApp LID display names without "
            "renaming Matrix rooms."
        )
    )
    parser.add_argument("action", choices=("inventory", "repair"))
    parser.add_argument(
        "--mapping",
        required=True,
        type=Path,
        help="Pipe-delimited LID-to-name file: <numeric LID>|<display name>",
    )
    parser.add_argument(
        "--registration",
        type=Path,
        default=Path("/whatsappdata/registration.yaml"),
        help="mautrix-whatsapp appservice registration",
    )
    parser.add_argument(
        "--homeserver-url",
        default="http://127.0.0.1:8008",
        help="Synapse client API base URL",
    )
    parser.add_argument("--server-name", default="h4xx.io")
    return parser.parse_args()


def load_mapping(path):
    mapping = {}
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            lid, name = line.split("|", 1)
        except ValueError as error:
            raise ValueError(f"{path}:{line_number}: expected <lid>|<name>") from error
        lid = lid.strip()
        name = name.strip()
        if not lid.isdigit():
            raise ValueError(f"{path}:{line_number}: LID must be numeric")
        if not name:
            raise ValueError(f"{path}:{line_number}: display name must not be empty")
        if lid in mapping and mapping[lid] != name:
            raise ValueError(
                f"{path}:{line_number}: conflicting names for LID {lid}: "
                f"{mapping[lid]!r} and {name!r}"
            )
        mapping[lid] = name
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


def unresolved_displayname(displayname, lid):
    return not displayname or displayname in {
        f"whatsapp_lid-{lid}",
        f"@whatsapp_lid-{lid}",
    }


def desired_displayname(name):
    return name if name.endswith(" (WA)") else f"{name} (WA)"


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
    mapping = load_mapping(args.mapping)
    client = MatrixClient(
        args.homeserver_url,
        load_appservice_token(args.registration),
    )
    changed_profiles = 0
    changed_memberships = 0
    skipped = 0
    errors = 0

    for lid, source_name in sorted(mapping.items(), key=lambda item: int(item[0])):
        user_id = f"@whatsapp_lid-{lid}:{args.server_name}"
        wanted_name = desired_displayname(source_name)
        try:
            profile = client.request(
                "GET",
                f"/_matrix/client/v3/profile/{encoded(user_id)}",
                acting_user=user_id,
            )
        except RuntimeError as error:
            if "HTTP 404:" in str(error):
                continue
            print(f"ERROR profile {user_id}: {error}", file=sys.stderr)
            errors += 1
            continue

        current_name = profile.get("displayname", "")
        profile_needs_update = unresolved_displayname(current_name, lid)
        if current_name != wanted_name and not profile_needs_update:
            skipped += 1
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
                "mapped_lids": len(mapping),
                "skipped_resolved_profiles": skipped,
            },
            sort_keys=True,
        )
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
