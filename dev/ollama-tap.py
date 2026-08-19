"""A proxy that records exactly what Home Assistant asks ollama for.

Reconstructing the prompt from the pieces has burned me before: what Home
Assistant sends is the template, the API preamble, the entity overview, the
tools and the options, assembled by code that has opinions. This forwards
everything to the real server and writes each request body to a file, so the
question "how big is the prompt, and what options are set" has an answer rather
than an estimate.

    dev/py dev/ollama-tap.py [--listen 11435] [--upstream 192.168.122.1:11434]

Then point the development instance's ollama entry at 127.0.0.1:11435.
"""
import argparse, asyncio, json, time
from aiohttp import ClientSession, web

JOURNAL = "scratch/ollama-requests.jsonl"


async def handle(request):
    body = await request.read()
    if request.path.endswith("/api/chat") and body:
        try:
            d = json.loads(body)
            with open(JOURNAL, "a") as f:
                f.write(json.dumps({"at": time.time(), "body": d}) + "\n")
            msgs = d.get("messages", [])
            chars = sum(len(m.get("content") or "") for m in msgs)
            print(f"  chat: {len(msgs)} messages, {chars} chars, "
                  f"{len(d.get('tools') or [])} tools, options={d.get('options')}, "
                  f"think={d.get('think')!r}, stream={d.get('stream')}", flush=True)
        except (ValueError, OSError):
            pass

    up = request.app["upstream"]
    async with request.app["session"].request(
        request.method, f"http://{up}{request.path_qs}", data=body or None,
        headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
    ) as r:
        resp = web.StreamResponse(status=r.status, headers={
            k: v for k, v in r.headers.items()
            if k.lower() not in ("content-length", "content-encoding",
                                 "transfer-encoding")})
        await resp.prepare(request)
        async for chunk in r.content.iter_any():
            await resp.write(chunk)
        await resp.write_eof()
        return resp


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", type=int, default=11435)
    parser.add_argument("--upstream", default="192.168.122.1:11434")
    args = parser.parse_args()

    app = web.Application(client_max_size=64 * 1024 * 1024)
    app["upstream"] = args.upstream
    app.router.add_route("*", "/{tail:.*}", handle)
    app.cleanup_ctx.append(session_ctx)
    open(JOURNAL, "w").close()
    print(f"tapping {args.upstream} on :{args.listen}, writing {JOURNAL}", flush=True)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", args.listen).start()
    await asyncio.Event().wait()


async def session_ctx(app):
    async with ClientSession(timeout=None) as s:
        app["session"] = s
        yield

asyncio.run(main())
