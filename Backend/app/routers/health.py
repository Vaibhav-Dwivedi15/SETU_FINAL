"""
Health check endpoint.

Confirms the API is up AND that it can actually reach the database --
a 200 here means both FastAPI and PostgreSQL are working, not just FastAPI.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.base import get_db

router = APIRouter()


@router.get("/health")
def health_check(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "connected"}