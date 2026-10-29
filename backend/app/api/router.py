"""Aggregates all API routes under /api/v1."""
from fastapi import APIRouter

from app.api.routes import (
    approvals,
    bookings,
    inquiries,
    leads,
    monitoring,
    qualification,
    team,
    workflows,
)
from app.core.config import API_PREFIX

api_router = APIRouter(prefix=API_PREFIX)

for module in (team, leads, qualification, inquiries, workflows, approvals, bookings, monitoring):
    api_router.include_router(module.router)

api_router.include_router(bookings.internal_router)