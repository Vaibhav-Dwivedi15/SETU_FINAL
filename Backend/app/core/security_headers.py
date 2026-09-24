"""Baseline security headers for every API response (Block 3). Pure ASGI, adds headers only."""

API_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"referrer-policy", b"no-referrer"),
    (b"cache-control", b"no-store"),  # incident/profile data must not sit in shared caches
    (b"cross-origin-resource-policy", b"same-site"),
    (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),  # meaningful behind TLS (Render terminates it)
    (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'"),  # API returns JSON only
    (b"x-frame-options", b"DENY"),
]


class SecurityHeadersMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                present = {k.lower() for k, _ in message.get("headers", [])}
                headers = list(message.get("headers", []))
                headers += [(k, v) for k, v in API_HEADERS if k not in present]
                message = {**message, "headers": headers}
            await send(message)

        await self.app(scope, receive, send_with_headers)
