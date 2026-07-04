"""Role map reload unit tests."""

from __future__ import annotations

import pytest

from gateway.auth.role_map import RoleMapStore


@pytest.fixture
def role_map() -> RoleMapStore:
    return RoleMapStore(
        {
            "administrator": True,
            "doctor": True,
            "receptionist": False,
            "lab_staff": False,
        }
    )


def test_default_roles(role_map: RoleMapStore) -> None:
    assert role_map.has_ai_access("administrator") is True
    assert role_map.has_ai_access("doctor") is True
    assert role_map.has_ai_access("receptionist") is False
    assert role_map.has_ai_access("lab_staff") is False


def test_unknown_role_denied(role_map: RoleMapStore) -> None:
    assert role_map.has_ai_access("unknown_role") is False


def test_atomic_reload_reflects_new_grants(role_map: RoleMapStore) -> None:
    assert role_map.has_ai_access("receptionist") is False
    role_map.reload({"receptionist": True})
    assert role_map.has_ai_access("receptionist") is True
    assert role_map.has_ai_access("doctor") is True


def test_atomic_reload_can_revoke_access(role_map: RoleMapStore) -> None:
    assert role_map.has_ai_access("doctor") is True
    role_map.reload({"doctor": False})
    assert role_map.has_ai_access("doctor") is False
    assert role_map.has_ai_access("administrator") is True


def test_reload_merges_with_defaults(role_map: RoleMapStore) -> None:
    role_map.reload({"lab_staff": True})
    assert role_map.has_ai_access("lab_staff") is True
    assert role_map.has_ai_access("receptionist") is False
