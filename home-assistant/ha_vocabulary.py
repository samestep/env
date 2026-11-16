"""Discover Assist entity names and aliases without reading private HA storage."""

import asyncio
import logging
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import aiohttp

LOGGER = logging.getLogger("qwen-asr.vocabulary")


def normalize(text):
    """Ignore case/punctuation while retaining Unicode letters and digits."""
    return " ".join(re.findall(r"\w+", text.casefold()))


@dataclass(frozen=True)
class Vocabulary:
    names: tuple[str, ...] = ()
    entities: dict[str, frozenset[str]] = field(default_factory=dict)

    @property
    def prompt(self):
        return "Vocabulary: " + ", ".join(self.names) + "." if self.names else None


def build_vocabulary(exposure, states, registry):
    """Only use current Assist-exposed entities and their spoken names."""
    exposed = exposure["exposed_entities"]
    entries = {entry["entity_id"]: entry for entry in registry}
    names = {}
    entities = {}
    for state in states:
        entity_id = state["entity_id"]
        if not exposed.get(entity_id, {}).get("conversation"):
            continue
        entry = entries.get(entity_id, {})
        if entry.get("disabled_by"):
            continue
        computed = (
            state.get("attributes", {}).get("friendly_name")
            or entry.get("name") or entry.get("original_name")
            or entity_id.split(".", 1)[-1].replace("_", " ")
        )
        if "aliases_v2" in entry:
            # None is HA's computed-name marker. An explicit alias list may
            # intentionally omit that name, so don't add it back ourselves.
            aliases = [computed if alias is None else alias
                       for alias in entry["aliases_v2"]]
        else:
            aliases = [computed, *entry.get("aliases", [])]
        for alias in aliases:
            if not isinstance(alias, str) or not (key := normalize(alias)):
                continue
            names.setdefault(key, alias.strip())
            entities.setdefault(key, set()).add(entity_id)
    keys = sorted(names)
    return Vocabulary(
        tuple(names[key] for key in keys),
        {key: frozenset(entities[key]) for key in keys},
    )


async def fetch_vocabulary(url, token):
    """Read a fresh snapshot via HA's authenticated WebSocket API."""
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Home Assistant URL must use http or https")
    ws_url = urlunsplit((
        "wss" if parsed.scheme == "https" else "ws", parsed.netloc,
        parsed.path.rstrip("/") + "/api/websocket", "", "",
    ))
    async with asyncio.timeout(10), aiohttp.ClientSession() as session:
        async with session.ws_connect(ws_url) as ws:
            if (await ws.receive_json()).get("type") != "auth_required":
                raise RuntimeError("Unexpected Home Assistant authentication response")
            await ws.send_json({"type": "auth", "access_token": token})
            if (await ws.receive_json()).get("type") != "auth_ok":
                raise RuntimeError("Home Assistant authentication failed")
            # Preparing Assist initializes effective default exposure settings;
            # the exposure-list endpoint otherwise reports stored settings only.
            await ws.send_json({"id": 1, "type": "conversation/prepare",
                                "agent_id": "conversation.home_assistant", "language": "en"})
            prepared = await ws.receive_json()
            if (prepared.get("id") != 1 or prepared.get("type") != "result"
                    or not prepared.get("success")):
                raise RuntimeError(f"Home Assistant could not prepare Assist vocabulary: {prepared.get('error', {})}")
            results = []
            for request_id, command in enumerate([
                "homeassistant/expose_entity/list",
                "get_states",
                "config/entity_registry/list",
            ], 2):
                await ws.send_json({"id": request_id, "type": command})
                response = await ws.receive_json()
                if (response.get("id") != request_id
                        or response.get("type") != "result"
                        or not response.get("success")):
                    raise RuntimeError(f"Home Assistant rejected {command}: {response.get('error', {})}")
                results.append(response["result"])
    return build_vocabulary(*results)


class RuntimeVocabulary:
    """Replace snapshots atomically; inference keeps one snapshot per request."""

    def __init__(self, url, token_file, refresh_seconds=60):
        self.url = url
        self.token_file = Path(token_file)
        self.refresh_seconds = refresh_seconds
        self.snapshot = Vocabulary()
        self.error = None
        self._loaded = False

    async def refresh(self):
        token = ""
        try:
            token = self.token_file.read_text().strip()
            if not token:
                raise ValueError("Empty Home Assistant token file")
            snapshot = await fetch_vocabulary(self.url, token)
        except (OSError, ValueError, RuntimeError, KeyError, TypeError,
                aiohttp.ClientError, TimeoutError) as error:
            # Stale exposed names could keep biasing removed/hidden devices.
            self.snapshot = Vocabulary()
            detail = f"{type(error).__name__}: {error}"
            if token:
                detail = detail.replace(token, "<redacted>")
            if detail != self.error:
                LOGGER.warning(
                    "Home Assistant vocabulary unavailable; decoding without hints: %s",
                    detail,
                )
            self.error = detail
            return
        if not self._loaded or self.error is not None or snapshot != self.snapshot:
            LOGGER.info("Loaded %d Assist names/aliases from Home Assistant: %s",
                        len(snapshot.names), json.dumps(snapshot.names, ensure_ascii=False))
        self.error = None
        self._loaded = True
        self.snapshot = snapshot

    async def run(self):
        while True:
            await asyncio.sleep(self.refresh_seconds)
            await self.refresh()
