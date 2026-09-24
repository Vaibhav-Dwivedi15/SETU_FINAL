"""
Request-body size cap that does NOT rely on the Content-Length header
(Block 2). A pure ASGI middleware:

  1. Content-Length present and over the cap  -> 413 immediately (no body read).
  2. Otherwise (missing / lying header, chunked transfer) the ASGI `receive`
     channel is wrapped and BYTES ARE COUNTED as they stream in; the request is
     aborted with 413 the moment the cap is exceeded, whatever the headers said.

Caps are per path so a normal JSON call cannot carry a voice-sized body:
"""

from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse

DEFAULT_LIMIT_BYTES = 64 * 1024                 # register, auth, respond, ... (KBs in practice)
INGEST_LIMIT_BYTES = 2_600_000                  # 500 packets x 4096 B (MAX_PACKET_BYTES) + envelope
VOICE_LIMIT_BYTES = 26 * 1024 * 1024            # 25 MB audio (voice.MAX_AUDIO_BYTES) + form fields

PATH_LIMITS = {
    "/ingest": INGEST_LIMIT_BYTES,
    "/ingest/voice": VOICE_LIMIT_BYTES,
}


class BodySizeLimitMiddleware:
    def __init__(self, app, path_limits=None, default_limit=DEFAULT_LIMIT_BYTES):
        self.app = app
        self.path_limits = path_limits or PATH_LIMITS
        self.default_limit = default_limit

    def _limit_for(self, path: str) -> int:
        return self.path_limits.get(path, self.default_limit)

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        limit = self._limit_for(scope.get("path", ""))
        headers = {k.lower(): v for k, v in scope.get("headers", [])}

        declared = headers.get(b"content-length")
        if declared is not None:
            try:
                if int(declared) > limit:
                    await self._reject(scope, receive, send)
                    return
            except ValueError:
                response = JSONResponse({"detail": "Invalid Content-Length header."}, status_code=400)
                await response(scope, receive, send)
                return

        received = 0
        response_started = False

        async def limited_receive():
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise HTTPException(status_code=413, detail="Request body too large.")
            return message

        async def tracking_send(message):
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except HTTPException as exc:
            if exc.status_code == 413 and not response_started:
                await self._reject(scope, receive, send)
            else:
                raise

    @staticmethod
    async def _reject(scope, receive, send):
        response = JSONResponse({"detail": "Request body too large."}, status_code=413)
        await response(scope, receive, send)
