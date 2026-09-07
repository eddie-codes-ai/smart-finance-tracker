"""
The small part of Experta this project actually used.

Experta is a CLIPS-style expert system, and its reason for existing is the RETE
algorithm: incremental matching of many rules against many facts, where rules
chain into one another and re-evaluating everything on each change would be
expensive.

None of that applies here. knowledge_engine.run_analysis() declares exactly one
FinancialProfile, calls run(), and stops. No rule declares a new fact, so
nothing chains. Every one of the 55 rules in rules.py is a single pattern over
that one fact whose fields are either a literal or a P(...) predicate - pure
conjunction, with no OR, NOT, MATCH, AS, TEST, EXISTS or salience anywhere in
the codebase. RETE was doing the work of 55 if-statements through a network
compiler, an agenda and a conflict-resolution strategy.

The cost of that was not performance, it was the interpreter: experta requires
frozendict==1.2, which imports collections.Mapping - removed in Python 3.10.
That single transitive pin held the entire backend on Python 3.9, which stopped
receiving security patches in October 2025.

So this module keeps the part that earned its place - the declarative DSL, which
lets 55 rules read as a table of thresholds instead of a 500-line if/elif chain -
and drops the engine underneath it. facts.py and rules.py change by one import
line each; the rules themselves are untouched.

Behaviour is matched to experta 1.9.4 deliberately, including the parts that are
arguably wrong (see validate() on unknown fields). Parity was verified by
snapshotting 4113 generated profiles through the old engine and diffing them
against this one.
"""


class P:
    """
    A predicate constraint on a field, as in P(lambda x: x < 0).

    Anything not wrapped in P is compared with ==, so a bare value in a pattern
    means equality: spending_trend='stable', budgets_set=0.
    """

    __slots__ = ("predicate",)

    def __init__(self, predicate):
        self.predicate = predicate

    def __call__(self, value):
        return bool(self.predicate(value))

    def __repr__(self):
        return "P(%r)" % (self.predicate,)


class Field:
    """A declared field on a Fact: its type, and whether it may be omitted."""

    __slots__ = ("type", "mandatory")

    def __init__(self, type, mandatory=False):
        self.type = type
        self.mandatory = mandatory

    def __repr__(self):
        return "Field(%s, mandatory=%r)" % (
            getattr(self.type, "__name__", self.type), self.mandatory)


class _FactMeta(type):
    """Collects Field declarations off the class body into _fields."""

    def __new__(mcs, name, bases, namespace):
        fields = {}
        for base in bases:
            fields.update(getattr(base, "_fields", {}))

        # Taken out of the namespace so FinancialProfile.savings_rate is not a
        # Field object shadowing anything; the schema lives in _fields instead.
        own = {key: value for key, value in namespace.items()
               if isinstance(value, Field)}
        for key in own:
            del namespace[key]

        cls = super().__new__(mcs, name, bases, namespace)
        fields.update(own)
        cls._fields = fields
        return cls


class Fact(metaclass=_FactMeta):
    """
    A bag of field values - either real data, or a pattern of constraints.

    The same class serves both roles, which is why __init__ validates nothing:
    a Fact built inside @Rule(...) holds P objects and only a handful of the
    fields, and validating it as though it were data would reject every rule in
    the file. Validation happens in declare(), on real data only - exactly where
    experta does it.
    """

    def __init__(self, **values):
        self._values = values

    def __getitem__(self, key):
        return self._values[key]

    def __contains__(self, key):
        return key in self._values

    def get(self, key, default=None):
        return self._values.get(key, default)

    def keys(self):
        return self._values.keys()

    def items(self):
        return self._values.items()

    def __repr__(self):
        inner = ", ".join("%s=%r" % kv for kv in sorted(self._values.items()))
        return "%s(%s)" % (type(self).__name__, inner)

    def validate(self):
        """
        Check declared data against the field schema, raising ValueError.

        Unknown fields are accepted rather than rejected. That is not an
        oversight: experta accepts them too, and this module's contract is
        parity with what it replaced, not an improvement on it. Tightening it
        would risk turning a silently-ignored typo into a 500 at exactly the
        moment nobody is watching.
        """
        for name, field in self._fields.items():
            if name not in self._values:
                if field.mandatory:
                    raise ValueError(
                        "Mandatory field %r is not defined for fact %r"
                        % (name, self))
                continue

            value = self._values[name]
            if not isinstance(value, field.type):
                raise ValueError(
                    "Invalid value on field %r for fact %r: expected %s, got %s"
                    % (name, self,
                       getattr(field.type, "__name__", field.type),
                       type(value).__name__))


def _matches(pattern, fact):
    """
    True when every constraint in the pattern holds against the fact.

    A field named by the pattern but absent from the fact does not match, which
    is what makes a pattern a conjunction rather than a partial filter.
    """
    if not isinstance(fact, type(pattern)):
        return False

    for name, constraint in pattern.items():
        if name not in fact:
            return False

        value = fact[name]
        if isinstance(constraint, P):
            if not constraint(value):
                return False
        elif constraint != value:
            return False

    return True


class Rule:
    """
    Decorator recording the pattern a method fires on.

    Experta accepts several patterns in one @Rule, meaning a join across
    several facts. Nothing here does that, and implementing a join nobody uses
    would be the same mistake as keeping RETE - so more than one pattern is
    refused loudly rather than silently ignored.
    """

    def __init__(self, *patterns):
        if len(patterns) != 1:
            raise TypeError(
                "Rule takes exactly one pattern; got %d. Matching across "
                "several facts is not supported - see the module docstring."
                % len(patterns))
        self.pattern = patterns[0]

    def __call__(self, method):
        method._expert_pattern = self.pattern
        return method


class _EngineMeta(type):
    """Collects @Rule-decorated methods, in definition order."""

    def __new__(mcs, name, bases, namespace):
        cls = super().__new__(mcs, name, bases, namespace)

        # Reversed MRO so a subclass overriding a rule replaces the base one
        # rather than adding a second copy. Class namespaces preserve source
        # order, so rules fire in the order they are written.
        rules = {}
        for klass in reversed(cls.__mro__):
            for attr, value in vars(klass).items():
                if callable(value) and hasattr(value, "_expert_pattern"):
                    rules[attr] = value

        cls._rules = tuple(rules.items())
        return cls


class KnowledgeEngine(metaclass=_EngineMeta):
    """
    Declare facts, then run every rule whose pattern matches.

    Rules fire in the order they are defined. Experta made no such guarantee -
    its agenda ordering is why rules.py sorts advice by severity afterwards
    rather than trusting the order it gets back. Determinism here is a small
    improvement, and costs nothing: note() only ever subtracts from a score,
    so the total does not depend on the order at all.
    """

    def __init__(self):
        self.facts = []

    def reset(self):
        self.facts = []

    def declare(self, fact):
        fact.validate()
        self.facts.append(fact)
        return fact

    def run(self):
        facts = tuple(self.facts)
        for _name, method in self._rules:
            pattern = method._expert_pattern
            for fact in facts:
                if _matches(pattern, fact):
                    method(self)
