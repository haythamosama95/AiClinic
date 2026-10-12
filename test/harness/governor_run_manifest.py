"""Governor batch run plan (``run.json``) and resume helpers."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

from harness.campaign_config import load_campaign_config, resolve_campaign_config_path
from harness.common import REPO_ROOT, governor_campaign_log_dir, test_results_root, utc_now_iso

RUN_MANIFEST_NAME = "run.json"
MANIFEST_VERSION = 1

CampaignRunStatus = Literal["pending", "running", "finished", "failed"]


@dataclass(frozen=True)
class CampaignPlanEntry:
    area: str
    subcampaign: str
    config: dict[str, Any] | None
    config_path: str | None
    status: CampaignRunStatus
    exit_code: int | None
    log_dir: str


def latest_governor_run_dir() -> Path:
    """Most recent governor batch run (by directory mtime) that has ``run.json``."""
    governor_root = test_results_root() / "governor"
    if not governor_root.is_dir():
        raise FileNotFoundError(f"no governor runs under {governor_root}")
    candidates = [
        child
        for child in governor_root.iterdir()
        if child.is_dir() and (child / RUN_MANIFEST_NAME).is_file()
    ]
    if not candidates:
        raise FileNotFoundError(
            f"no governor runs with {RUN_MANIFEST_NAME} under {governor_root}"
        )
    return max(candidates, key=lambda path: path.stat().st_mtime)


def resolve_governor_run_dir(path: str | Path) -> Path:
    """Accept ``latest``, a governor run directory, or a path to ``run.json``."""
    if str(path).strip().lower() == "latest":
        return latest_governor_run_dir()
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = (REPO_ROOT / candidate).resolve()
    else:
        candidate = candidate.resolve()
    if candidate.is_file() and candidate.name == RUN_MANIFEST_NAME:
        return candidate.parent
    if candidate.is_dir() and (candidate / RUN_MANIFEST_NAME).is_file():
        return candidate
    if candidate.is_dir():
        return candidate
    raise FileNotFoundError(f"governor run not found: {path}")


def manifest_path(run_root: Path) -> Path:
    return run_root.resolve() / RUN_MANIFEST_NAME


def _relative_to_repo(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def _config_path_relative(area: str, subcampaign: str) -> str | None:
    path = resolve_campaign_config_path(area, subcampaign)
    if path is None:
        return None
    return _relative_to_repo(path)


def build_campaign_entry(
    area: str,
    subcampaign: str,
    *,
    run_root: Path,
    status: CampaignRunStatus = "pending",
    exit_code: int | None = None,
) -> dict[str, Any]:
    config = load_campaign_config(area, subcampaign)
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    return {
        "area": area,
        "subcampaign": subcampaign,
        "config": config,
        "config_path": _config_path_relative(area, subcampaign),
        "status": status,
        "exit_code": exit_code,
        "log_dir": log_dir.relative_to(run_root.resolve()).as_posix(),
    }


def write_run_manifest(
    run_root: Path,
    picked: list[tuple[str, str]],
    *,
    resumed_from: Path | None = None,
    previous_continued_at: list[str] | None = None,
) -> Path:
    run_root = run_root.resolve()
    run_root.mkdir(parents=True, exist_ok=True)
    path = manifest_path(run_root)
    continued: list[str] = list(previous_continued_at or [])
    if resumed_from is not None:
        continued.append(utc_now_iso())

    existing_doc: dict[str, Any] = {}
    if path.is_file():
        try:
            existing_doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            existing_doc = {}

    existing_campaigns: dict[tuple[str, str], dict[str, Any]] = {}
    for entry in existing_doc.get("campaigns", []):
        key = (entry.get("area"), entry.get("subcampaign"))
        if key[0] and key[1]:
            existing_campaigns[key] = entry

    campaigns: list[dict[str, Any]] = []
    for area, sub_id in picked:
        key = (area, sub_id)
        prior = existing_campaigns.get(key)
        if prior is not None:
            campaigns.append(prior)
            continue
        campaigns.append(build_campaign_entry(area, sub_id, run_root=run_root))

    started_at = existing_doc.get("started_at") if resumed_from is not None else None
    if not started_at:
        started_at = utc_now_iso()

    payload: dict[str, Any] = {
        "version": MANIFEST_VERSION,
        "run_id": run_root.name,
        "run_root": str(run_root),
        "run_root_relative": _relative_to_repo(run_root),
        "started_at": started_at,
        "continued_at": continued,
        "campaigns": campaigns,
    }
    if resumed_from is not None:
        payload["resumed_from"] = str(resumed_from.resolve())
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def load_run_manifest(run_root: Path) -> dict[str, Any]:
    path = manifest_path(run_root)
    if not path.is_file():
        raise FileNotFoundError(f"missing {RUN_MANIFEST_NAME} in {run_root}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != MANIFEST_VERSION:
        raise ValueError(f"unsupported {RUN_MANIFEST_NAME} version: {data.get('version')}")
    return data


def picked_from_manifest(data: dict[str, Any]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for entry in data.get("campaigns", []):
        area = entry.get("area")
        sub = entry.get("subcampaign")
        if isinstance(area, str) and isinstance(sub, str):
            out.append((area, sub))
    return out


def read_campaign_exit_code(run_root: Path, area: str, subcampaign: str) -> int | None:
    log_dir = governor_campaign_log_dir(run_root, area, subcampaign)
    summary = log_dir / "summary.json"
    if not summary.is_file():
        return None
    try:
        payload = json.loads(summary.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    code = payload.get("exit_code")
    return int(code) if code is not None else None


def campaign_resume_status(
    run_root: Path,
    area: str,
    subcampaign: str,
) -> CampaignRunStatus:
    code = read_campaign_exit_code(run_root, area, subcampaign)
    if code is None:
        return "pending"
    if code == 0:
        return "finished"
    return "failed"


def update_manifest_campaign(
    run_root: Path,
    area: str,
    subcampaign: str,
    *,
    status: CampaignRunStatus,
    exit_code: int | None,
) -> None:
    path = manifest_path(run_root)
    if not path.is_file():
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    for entry in data.get("campaigns", []):
        if entry.get("area") == area and entry.get("subcampaign") == subcampaign:
            entry["status"] = status
            entry["exit_code"] = exit_code
            break
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def sync_manifest_from_disk(run_root: Path) -> None:
    """Refresh per-campaign status fields from on-disk ``summary.json`` files."""
    path = manifest_path(run_root)
    if not path.is_file():
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    for entry in data.get("campaigns", []):
        area = entry.get("area")
        sub = entry.get("subcampaign")
        if not isinstance(area, str) or not isinstance(sub, str):
            continue
        status = campaign_resume_status(run_root, area, sub)
        entry["status"] = status
        if status == "pending":
            entry["exit_code"] = None
        else:
            entry["exit_code"] = read_campaign_exit_code(run_root, area, sub)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def should_skip_campaign_on_resume(
    run_root: Path,
    area: str,
    subcampaign: str,
) -> bool:
    return campaign_resume_status(run_root, area, subcampaign) == "finished"
