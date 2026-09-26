import importlib.util
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / ".codex" / "ensure_model_policy.py"
SPEC = importlib.util.spec_from_file_location("linux_ensure_model_policy", MODULE_PATH)
assert SPEC and SPEC.loader
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)


def _temp_codex_home(tmp_path: Path) -> Path:
    home = tmp_path / "codex-home"
    POLICY.apply(home, ROOT)
    return home


def test_crlf_only_role_file_is_accepted_without_policy_drift(tmp_path: Path) -> None:
    home = _temp_codex_home(tmp_path)
    role = home / "agents" / "default.toml"
    data = role.read_bytes()
    alternate = data.replace(b"\r\n", b"\n") if b"\r\n" in data else data.replace(b"\n", b"\r\n")
    role.write_bytes(alternate)

    POLICY.check(home, ROOT)


def test_semantic_model_drift_in_role_file_is_still_rejected(tmp_path: Path) -> None:
    home = _temp_codex_home(tmp_path)
    role = home / "agents" / "default.toml"
    role.write_bytes(role.read_bytes().replace(b'gpt-6-luna', b'gpt-6-astra', 1))

    with pytest.raises(POLICY.PolicyDrift, match="role template drift: default"):
        POLICY.check(home, ROOT)


def test_medium_root_reasoning_effort_is_rejected_and_apply_preserves_other_settings(
    tmp_path: Path,
) -> None:
    home = _temp_codex_home(tmp_path)
    config = home / "config.toml"
    config.write_bytes(
        b'approval_policy = "never"\n'
        + config.read_bytes().replace(
            b'model_reasoning_effort = "high"',
            b'model_reasoning_effort = "medium"',
            1,
        )
    )
    before = {path: path.read_bytes() for path in home.rglob("*") if path.is_file()}

    with pytest.raises(POLICY.PolicyDrift, match="root reasoning effort policy drift"):
        POLICY.check(home, ROOT)
    assert {path: path.read_bytes() for path in home.rglob("*") if path.is_file()} == before

    POLICY.apply(home, ROOT)
    after = POLICY.parse_config(config)
    assert after["model_reasoning_effort"] == "high"
    assert after["approval_policy"] == "never"
