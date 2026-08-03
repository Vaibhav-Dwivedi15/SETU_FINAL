"""
SETU AI - Logging Setup

Was an empty stub before. Basic structured console logging — one
shared format across the service, configured once.
"""

import logging

_configured = False


def get_logger(name: str) -> logging.Logger:
    global _configured
    if not _configured:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        )
        _configured = True
    return logging.getLogger(name)
