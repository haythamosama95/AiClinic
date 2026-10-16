"""Campaign log session layout."""

from pathlib import Path

from harness.campaign_logging import CampaignLogSession, slug_for_test_log


def test_slug_and_summary(tmp_path: Path) -> None:
    assert slug_for_test_log("Visit medical records: foo.sql") == "visit-medical-records-foo-sql"
    session = CampaignLogSession(tmp_path)
    session.start_test("alpha")
    session.append_output("hello\n")
    session.end_test("alpha", status="PASS")
    summary = session.write_summary(exit_code=0)
    assert (tmp_path / "summary.json").is_file()
    assert (tmp_path / "meta.json").is_file()
    assert len(summary["tests"]) == 1
    log_file = tmp_path / summary["tests"][0]["log_file"]
    assert log_file.is_file()
    assert "hello" in log_file.read_text(encoding="utf-8")


def test_start_test_same_name_keeps_open_log(tmp_path: Path) -> None:
    session = CampaignLogSession(tmp_path)
    session.start_test("alpha")
    session.append_output("line1\n")
    session.start_test("alpha")
    session.append_output("line2\n")
    session.end_test("alpha", status="PASS")
    summary = session.write_summary(exit_code=0)
    assert len(summary["tests"]) == 1
    log_file = tmp_path / summary["tests"][0]["log_file"]
    text = log_file.read_text(encoding="utf-8")
    assert "line1" in text and "line2" in text


def test_abort_current_test_drops_in_flight_without_summary_entry(tmp_path: Path) -> None:
    session = CampaignLogSession(tmp_path)
    session.start_test("alpha")
    session.append_output("partial\n")
    session.abort_current_test()
    session.start_test("beta")
    session.end_test("beta", status="PASS")
    summary = session.write_summary(exit_code=0, interrupted=True)
    assert len(summary["tests"]) == 1
    assert summary["tests"][0]["name"] == "beta"
    assert not any(path.name.startswith("001-") for path in (tmp_path / "tests").iterdir())
