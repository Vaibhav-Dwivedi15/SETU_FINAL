"""Shared request-parameter types (Block 2 input robustness)."""

from typing import Annotated

from fastapi import Path

# Incident ids are 32-bit serial primary keys. Bounding the path parameter turns
# absurd values (e.g. 99999999999999999999, which would raise a database
# "integer out of range" error => HTTP 500) into a controlled 422.
IncidentId = Annotated[int, Path(ge=1, le=2_147_483_647)]
