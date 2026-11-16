"""Run with the Qwen Python environment; no model downloads or GPU required."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from aiohttp import web

from ha_vocabulary import RuntimeVocabulary, Vocabulary, build_vocabulary, fetch_vocabulary, normalize

spec = importlib.util.spec_from_file_location("qwen_asr", Path(__file__).with_name("qwen-asr.py"))
qwen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qwen)


def fixture():
    return (
        {"exposed_entities": {
            "light.couch": {"conversation": True},
            "switch.orb": {"conversation": True},
            "light.private": {"cloud.alexa": True},
            "light.disabled": {"conversation": True},
        }},
        [
            {"entity_id": "light.couch", "attributes": {"friendly_name": "Couch lamp"}},
            {"entity_id": "switch.orb", "attributes": {"friendly_name": "Orb"}},
            {"entity_id": "light.private", "attributes": {"friendly_name": "Private lamp"}},
            {"entity_id": "light.disabled", "attributes": {"friendly_name": "Disabled lamp"}},
        ],
        [
            {"entity_id": "light.couch", "aliases_v2": [None, "Sofa lamp"]},
            {"entity_id": "switch.orb", "aliases": []},
            {"entity_id": "light.disabled", "disabled_by": "user"},
        ],
    )


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.vocabulary = build_vocabulary(*fixture())

    def select(self, candidates):
        return qwen.select_transcript(candidates, self.vocabulary)

    def test_recovers_real_alternative(self):
        self.assertEqual(self.select([
            "Turn on the capsule.", "Turn on the capsule lamp.", "Turn on the couch lamp."
        ]), ("Turn on the couch lamp.", 3))

    def test_preserves_action(self):
        self.assertEqual(self.select(["Turn off capsule.", "Turn on couch lamp."]),
                         ("Turn off capsule.", 1))
        self.assertEqual(self.select(["Turn off capsule.", "Turn off couch lamp."]),
                         ("Turn off couch lamp.", 2))

    def test_known_first_choice_wins(self):
        self.assertEqual(self.select(["Turn on orb.", "Turn on couch lamp."]),
                         ("Turn on orb.", 1))

    def test_ambiguous_devices_are_not_resolved(self):
        self.assertEqual(self.select([
            "Turn on capsule.", "Turn on couch lamp.", "Turn on orb."
        ]), ("Turn on capsule.", 1))

    def test_aliases_of_one_device_are_not_ambiguous(self):
        self.assertEqual(self.select([
            "Turn on capsule.", "Turn on sofa lamp.", "Turn on couch lamp."
        ]), ("Turn on sofa lamp.", 2))

    def test_shared_alias_is_ambiguous(self):
        exposure, states, registry = fixture()
        registry[0]["aliases_v2"].append("Lamp")
        registry[1]["aliases"] = ["Lamp"]
        self.vocabulary = build_vocabulary(exposure, states, registry)
        self.assertEqual(self.select(["Turn on capsule.", "Turn on lamp."]),
                         ("Turn on capsule.", 1))

    def test_general_and_compound_speech_stays_unchanged(self):
        for text in ["I bought a capsule lamp.", "Turn on the orb and the couch lamp.",
                     "Turn off capsule, not orb."]:
            self.assertEqual(self.select([text, "Turn on couch lamp.", "Turn off orb."]),
                             (text, 1))

    def test_foreign_suffix_is_not_erased(self):
        self.assertEqual(self.select(["Turn on capsule.", "Turn on couch lamp. روشن"]),
                         ("Turn on capsule.", 1))

    def test_reordered_command_and_empty_output(self):
        self.assertEqual(self.select(["Turn the capsule off.", "Turn the couch lamp off."]),
                         ("Turn the couch lamp off.", 2))
        self.assertEqual(self.select([]), ("", 0))


class VocabularyTests(unittest.TestCase):
    def test_only_exposed_enabled_entities_and_aliases(self):
        vocabulary = build_vocabulary(*fixture())
        self.assertEqual(vocabulary.names, ("Couch lamp", "Orb", "Sofa lamp"))
        self.assertEqual(vocabulary.entities["sofa lamp"], frozenset({"light.couch"}))

    def test_explicit_alias_list_does_not_restore_omitted_name(self):
        exposure, states, registry = fixture()
        registry[0]["aliases_v2"] = ["Sofa lamp"]
        self.assertNotIn("couch lamp", build_vocabulary(exposure, states, registry).entities)


class WebsocketTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.payloads = fixture()
        self.bad_auth = False
        self.rejected_command = None
        self.requests = []
        app = web.Application()
        app.router.add_get("/api/websocket", self.handle)
        self.runner = web.AppRunner(app)
        await self.runner.setup()
        site = web.TCPSite(self.runner, "127.0.0.1", 0)
        await site.start()
        port = site._server.sockets[0].getsockname()[1]
        self.url = f"http://127.0.0.1:{port}"
        self.temp = tempfile.TemporaryDirectory()
        self.token_file = Path(self.temp.name) / "token"
        self.token_file.write_text("test-token\n")

    async def asyncTearDown(self):
        await self.runner.cleanup()
        self.temp.cleanup()

    async def handle(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        await ws.send_json({"type": "auth_required"})
        auth = await ws.receive_json()
        self.assertEqual(auth, {"type": "auth", "access_token": "test-token"})
        if self.bad_auth:
            await ws.send_json({"type": "auth_invalid"})
            return ws
        await ws.send_json({"type": "auth_ok"})
        prepare = await ws.receive_json()
        self.assertEqual(prepare, {"id": 1, "type": "conversation/prepare",
                                   "agent_id": "conversation.home_assistant", "language": "en"})
        self.requests.append(prepare["type"])
        await ws.send_json({"id": 1, "type": "result", "success": True})
        for payload in self.payloads:
            command = await ws.receive_json()
            self.requests.append(command["type"])
            if command["type"] == self.rejected_command:
                await ws.send_json({"id": command["id"], "type": "result", "success": False})
                return ws
            await ws.send_json({"id": command["id"], "type": "result", "success": True,
                                "result": payload})
        await ws.close()
        return ws

    async def test_real_handshake_and_read_only_queries(self):
        snapshot = await fetch_vocabulary(self.url, "test-token")
        self.assertIn("couch lamp", snapshot.entities)
        self.assertEqual(self.requests, ["conversation/prepare", "homeassistant/expose_entity/list", "get_states",
                                        "config/entity_registry/list"])

    async def test_renames_and_exposure_changes_refresh_without_restart(self):
        runtime = RuntimeVocabulary(self.url, self.token_file)
        with self.assertLogs("qwen-asr.vocabulary", "INFO") as logs:
            await runtime.refresh()
        self.assertIn("Couch lamp", str(logs.output))
        self.assertIn("Sofa lamp", str(logs.output))
        old = runtime.snapshot
        self.payloads[0]["exposed_entities"].pop("switch.orb")
        self.payloads[1][0]["attributes"]["friendly_name"] = "Reading lamp"
        await runtime.refresh()
        self.assertIn("couch lamp", old.entities)  # In-flight snapshots remain stable.
        self.assertNotIn("couch lamp", runtime.snapshot.entities)
        self.assertNotIn("orb", runtime.snapshot.entities)
        self.assertIn("reading lamp", runtime.snapshot.entities)

    async def test_auth_failure_clears_stale_hints_without_logging_token(self):
        runtime = RuntimeVocabulary(self.url, self.token_file)
        await runtime.refresh()
        self.bad_auth = True
        with self.assertLogs("qwen-asr.vocabulary", "WARNING") as logs:
            await runtime.refresh()
        self.assertEqual(runtime.snapshot, Vocabulary())
        self.assertNotIn("test-token", str(logs.output))
        self.assertIn("authentication failed", str(logs.output))

    async def test_missing_credential_and_permission_denial_are_nonfatal(self):
        runtime = RuntimeVocabulary(self.url, self.token_file)
        self.token_file.unlink()
        with self.assertLogs("qwen-asr.vocabulary", "WARNING"):
            await runtime.refresh()
        self.assertEqual(runtime.snapshot, Vocabulary())
        self.token_file.write_text("test-token")
        self.rejected_command = "homeassistant/expose_entity/list"
        with self.assertLogs("qwen-asr.vocabulary", "WARNING") as logs:
            await runtime.refresh()
        self.assertIn("Home Assistant rejected homeassistant/expose_entity/list", str(logs.output))
        self.assertEqual(runtime.snapshot, Vocabulary())


if __name__ == "__main__":
    unittest.main()
