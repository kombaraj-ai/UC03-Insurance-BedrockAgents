import pytest

from session_id import derive_session_id


def test_same_sub_always_yields_same_session_id():
    assert derive_session_id("user-abc") == derive_session_id("user-abc")


def test_different_subs_yield_different_session_ids():
    assert derive_session_id("user-abc") != derive_session_id("user-xyz")


def test_session_id_uses_only_allowed_characters():
    session_id = derive_session_id("user-abc")
    assert all(c.isalnum() or c in "._:-" for c in session_id)
    assert len(session_id) <= 100


def test_empty_sub_is_rejected():
    with pytest.raises(ValueError):
        derive_session_id("")
