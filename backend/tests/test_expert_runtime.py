"""
Unit tests for engine/expert.py - the rule runner that replaced Experta.

test_engine_scoring.py covers what the rules *decide*. This file covers the
machinery underneath them: field validation, pattern matching, and rule
collection. The two are separate on purpose - a scoring bug and a matching bug
need different fixes, and a failure here should point straight at the runtime
rather than at 55 thresholds.

Every behaviour asserted below was first measured against experta 1.9.4, so
these are parity tests, not a specification written after the fact. The one
that most deserves suspicion is unknown fields being accepted: that is
experta's behaviour, and it is preserved deliberately.

Run it directly, no pytest needed:

    cd backend
    venv/Scripts/python tests/test_expert_runtime.py     # Windows
    venv/bin/python tests/test_expert_runtime.py         # Linux/macOS
"""
import os
import sys

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND_DIR)

from engine.expert import (Fact, Field, KnowledgeEngine, P,  # noqa: E402
                           Rule)


class Sample(Fact):
    name     = Field(str,   mandatory=True)
    count    = Field(int,   mandatory=True)
    ratio    = Field(float, mandatory=True)
    flag     = Field(bool,  mandatory=True)
    optional = Field(str,   mandatory=False)


VALID = dict(name="a", count=1, ratio=1.0, flag=True)


def declare(**overrides):
    """Declare a Sample into a bare engine, returning the engine."""
    values = dict(VALID)
    values.update(overrides)
    engine = KnowledgeEngine()
    engine.reset()
    engine.declare(Sample(**values))
    return engine


def raises_value_error(fn):
    try:
        fn()
    except ValueError:
        return True
    return False


# ── Validation happens on declare, not construction ───────────────────────────

def test_a_pattern_is_not_validated_when_built():
    """
    Every @Rule in rules.py builds a FinancialProfile holding two or three
    fields and P objects. Validating at construction would reject all 55.
    """
    Sample(count=P(lambda x: x > 0))          # no name, no ratio, no flag
    Sample()                                   # entirely empty


def test_a_valid_fact_declares_cleanly():
    declare()


def test_missing_mandatory_field_is_rejected():
    engine = KnowledgeEngine()
    values = dict(VALID)
    del values["count"]
    assert raises_value_error(lambda: engine.declare(Sample(**values)))


def test_missing_optional_field_is_fine():
    declare()   # `optional` is never supplied anywhere in this file


def test_wrong_type_is_rejected():
    """
    Each of these raised ValueError under experta. int-for-float matters most:
    knowledge_engine coerces with _safe_float precisely because of it.
    """
    for field, bad in (("name", 1), ("count", 1.5), ("ratio", 1), ("flag", 1)):
        values = dict(VALID)
        values[field] = bad
        engine = KnowledgeEngine()
        assert raises_value_error(lambda: engine.declare(Sample(**values))), \
            "%s=%r should have been rejected" % (field, bad)


def test_unknown_fields_are_accepted():
    """
    Experta accepts them, so this does too. Asserted rather than left
    undefined: if someone later decides to tighten it, this test should be the
    thing that makes them think about the 500 it could cause in production.
    """
    declare(no_such_field=123)


# ── Pattern matching ──────────────────────────────────────────────────────────

class Matcher(KnowledgeEngine):
    def __init__(self):
        super().__init__()
        self.fired = []

    @Rule(Sample(flag=True))
    def literal_true(self):
        self.fired.append("literal_true")

    @Rule(Sample(name="a"))
    def literal_string(self):
        self.fired.append("literal_string")

    @Rule(Sample(count=P(lambda x: x > 10)))
    def predicate_over_ten(self):
        self.fired.append("predicate_over_ten")

    @Rule(Sample(flag=True, count=P(lambda x: x > 10)))
    def both_conditions(self):
        self.fired.append("both_conditions")

    @Rule(Sample(optional="present"))
    def names_an_absent_field(self):
        self.fired.append("names_an_absent_field")


def fire(**overrides):
    values = dict(VALID)
    values.update(overrides)
    m = Matcher()
    m.reset()
    m.declare(Sample(**values))
    m.run()
    return m.fired


def test_a_literal_matches_by_equality():
    assert "literal_true" in fire(flag=True)
    assert "literal_true" not in fire(flag=False)
    assert "literal_string" in fire(name="a")
    assert "literal_string" not in fire(name="b")


def test_a_predicate_matches_by_calling_it():
    assert "predicate_over_ten" in fire(count=11)
    assert "predicate_over_ten" not in fire(count=10)


def test_all_conditions_must_hold():
    """A pattern is a conjunction: two out of three is no match."""
    assert "both_conditions" in fire(flag=True, count=11)
    assert "both_conditions" not in fire(flag=True, count=1)
    assert "both_conditions" not in fire(flag=False, count=11)


def test_a_field_absent_from_the_fact_does_not_match():
    """Otherwise an unset field would silently satisfy any constraint on it."""
    assert "names_an_absent_field" not in fire()
    assert "names_an_absent_field" in fire(optional="present")


def test_a_rule_fires_once_per_run():
    assert fire(flag=True).count("literal_true") == 1


def test_nothing_fires_before_a_fact_is_declared():
    m = Matcher()
    m.reset()
    m.run()
    assert m.fired == []


def test_reset_clears_declared_facts():
    m = Matcher()
    m.reset()
    m.declare(Sample(**VALID))
    m.reset()
    m.run()
    assert m.fired == [], m.fired


# ── Rule collection ───────────────────────────────────────────────────────────

def test_every_decorated_method_is_collected():
    names = {name for name, _ in Matcher._rules}
    assert names == {"literal_true", "literal_string", "predicate_over_ten",
                     "both_conditions", "names_an_absent_field"}, names


def test_rules_are_collected_in_definition_order():
    """
    Not relied on for correctness - advice is sorted by severity and penalties
    only ever subtract - but it is what makes output reproducible run to run,
    which experta's agenda did not guarantee.
    """
    assert [name for name, _ in Matcher._rules] == [
        "literal_true", "literal_string", "predicate_over_ten",
        "both_conditions", "names_an_absent_field"]


def test_the_real_advisor_collected_all_of_its_rules():
    from engine.rules import FinancialAdvisor
    assert len(FinancialAdvisor._rules) == 55, len(FinancialAdvisor._rules)


def test_a_multi_pattern_rule_is_refused():
    """
    Experta would treat this as a join across two facts. Nothing here does
    that, so it fails loudly rather than matching on the first pattern and
    quietly ignoring the second.
    """
    try:
        Rule(Sample(flag=True), Sample(count=1))
    except TypeError:
        return
    raise AssertionError("two patterns should have raised TypeError")


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
