"""
Tests for budget deletion.

Budgets could be created and updated but never removed: there was no DELETE
route, no provider method and nothing in the UI. A limit set once on a category
was permanent, and the only way out was raising it to something meaningless.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_budget_crud.py     # Windows
    venv/bin/python tests/test_budget_crud.py         # Linux/macOS
"""
import os
import sys
import tempfile
import uuid

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

_DB_PATH = os.path.join(tempfile.mkdtemp(prefix="sft-budget-"), "test.db")
os.environ["DATABASE_URL"] = "sqlite:///" + _DB_PATH.replace(os.sep, "/")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-not-used-in-production")

from flask_migrate import upgrade                                     # noqa: E402

from app import create_app                                            # noqa: E402

_app = create_app()
_app.config["PROPAGATE_EXCEPTIONS"] = False
_app.config["TESTING"] = True
with _app.app_context():
    upgrade()
CLIENT = _app.test_client()

MONTH = "2026-04"


def user():
    username = "b-" + uuid.uuid4().hex[:8]
    r = CLIENT.post("/api/auth/register",
                    json={"username": username, "password": "correct-horse"})
    assert r.status_code == 201, r.get_data(as_text=True)
    return {"Authorization": "Bearer " + r.get_json()["token"]}


def set_budget(headers, category="Food", limit=5000.0, month=MONTH):
    r = CLIENT.post("/api/budgets",
                    json={"category": category, "limit": limit, "month_year": month},
                    headers=headers)
    assert r.status_code == 201, r.get_data(as_text=True)


def budgets_for(headers, month=MONTH):
    r = CLIENT.get("/api/budgets?month_year=%s" % month, headers=headers)
    assert r.status_code == 200, r.get_data(as_text=True)
    return {b["category"]: b["limit"] for b in r.get_json()["budgets"]}


def delete_budget(headers, category="Food", month=MONTH):
    return CLIENT.delete("/api/budgets/%s?month_year=%s" % (category, month),
                         headers=headers)


# ── The gap ───────────────────────────────────────────────────────────────────

def test_a_budget_can_be_removed():
    h = user()
    set_budget(h)
    assert "Food" in budgets_for(h)

    r = delete_budget(h)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert "Food" not in budgets_for(h)


def test_removing_one_budget_leaves_the_others():
    h = user()
    set_budget(h, category="Food")
    set_budget(h, category="Transport")

    delete_budget(h, category="Food")
    remaining = budgets_for(h)
    assert "Food" not in remaining
    assert "Transport" in remaining


def test_a_removed_budget_can_be_set_again():
    """The unique constraint on (user, category, month) must not block reuse."""
    h = user()
    set_budget(h, limit=5000.0)
    delete_budget(h)
    set_budget(h, limit=7000.0)
    assert budgets_for(h)["Food"] == 7000.0


# ── Scoping ───────────────────────────────────────────────────────────────────

def test_deletion_is_scoped_to_one_month():
    h = user()
    set_budget(h, month="2026-04")
    set_budget(h, month="2026-05")

    delete_budget(h, month="2026-04")

    assert "Food" not in budgets_for(h, month="2026-04")
    assert "Food" in budgets_for(h, month="2026-05"), \
        "deleting April's budget also removed May's"


def test_one_user_cannot_delete_anothers_budget():
    owner, intruder = user(), user()
    set_budget(owner)

    r = delete_budget(intruder)
    assert r.status_code == 404, r.get_data(as_text=True)
    assert "Food" in budgets_for(owner), "another user's budget was deleted"


def test_deleting_a_budget_that_does_not_exist_is_404():
    h = user()
    r = delete_budget(h, category="Entertainment")
    assert r.status_code == 404
    assert "no budget found" in r.get_json()["message"].lower()


def test_deletion_requires_authentication():
    assert CLIENT.delete("/api/budgets/Food?month_year=%s" % MONTH).status_code == 401


def test_a_category_with_spaces_round_trips():
    """Custom categories can contain spaces, so the path segment is encoded."""
    h = user()
    set_budget(h, category="Chama contribution")
    r = CLIENT.delete("/api/budgets/Chama%%20contribution?month_year=%s" % MONTH,
                      headers=h)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert "Chama contribution" not in budgets_for(h)


# ── Contribution totals after the N+1 rewrite ─────────────────────────────────

def test_contribution_totals_survive_the_aggregate_rewrite():
    """
    Contributions used to be summed by loading every row for every goal, one
    query per goal. That is now a single grouped aggregate, so the figures it
    produces are worth pinning: an optimisation that changes a total is not an
    optimisation.
    """
    h = user()
    CLIENT.post("/api/income", json={"amount": 30000, "income_type": "monthly"},
                headers=h)

    goals = []
    for name, amount in [("Laptop", 50000), ("Trip", 20000), ("Books", 8000)]:
        r = CLIENT.post("/api/goals",
                        json={"name": name, "goal_amount": amount,
                              "due_date": "2026-12-01"}, headers=h)
        assert r.status_code == 201, r.get_data(as_text=True)
        goals.append(r.get_json()["goal"]["id"])

    # Several contributions each, so a per-goal loop and a grouped aggregate
    # could plausibly disagree.
    expected = 0.0
    for i, goal_id in enumerate(goals):
        for amount in (500.0 * (i + 1), 250.0, 125.5):
            r = CLIENT.post("/api/goals/%s/contribute" % goal_id,
                            json={"amount": amount}, headers=h)
            assert r.status_code == 201, r.get_data(as_text=True)
            expected += amount

    analysis = CLIENT.post("/api/analyze", json={}, headers=h).get_json()
    assert abs(analysis["total_contributions"] - expected) < 0.01,         "expected %s, got %s" % (expected, analysis["total_contributions"])


def test_a_goal_with_no_contributions_counts_as_zero():
    """The grouped query returns no row at all for such a goal."""
    h = user()
    CLIENT.post("/api/income", json={"amount": 10000, "income_type": "monthly"},
                headers=h)
    CLIENT.post("/api/goals",
                json={"name": "Untouched", "goal_amount": 5000,
                      "due_date": "2026-12-01"}, headers=h)

    analysis = CLIENT.post("/api/analyze", json={}, headers=h).get_json()
    assert analysis["total_contributions"] == 0


def test_no_goals_at_all_is_zero_not_an_error():
    h = user()
    CLIENT.post("/api/income", json={"amount": 10000, "income_type": "monthly"},
                headers=h)
    r = CLIENT.post("/api/analyze", json={}, headers=h)
    assert r.status_code == 200, r.get_data(as_text=True)
    assert r.get_json()["total_contributions"] == 0


# ── Health check ──────────────────────────────────────────────────────────────

def test_health_reports_the_database():
    """
    A container that boots but cannot reach its database looks healthy to a
    plain process check while failing every real request.
    """
    r = CLIENT.get("/health")
    assert r.status_code == 200, r.get_data(as_text=True)
    body = r.get_json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"


def test_health_needs_no_authentication():
    """A platform poller has no credentials."""
    assert CLIENT.get("/health").status_code == 200


# ── Runner ────────────────────────────────────────────────────────────────────

def main():
    tests = [(name, fn) for name, fn in sorted(globals().items())
             if name.startswith("test_") and callable(fn)]
    failures = []
    for name, fn in tests:
        try:
            fn()
            print("PASS  %s" % name)
        except AssertionError as e:
            failures.append(name)
            print("FAIL  %s\n      %s" % (name, e))
    print("\n%d/%d passed" % (len(tests) - len(failures), len(tests)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
