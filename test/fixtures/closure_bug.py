"""
Closure and scope bug — a classic Python gotcha.
The bug: lambda captures variable by reference, not by value,
so all callbacks refer to the same loop variable.
"""


def create_multipliers():
    """Create a list of multiplier functions."""
    multipliers = []
    for i in range(5):
        # Bug: lambda captures `i` by reference, not value
        # All lambdas will use i=4 (final loop value)
        multipliers.append(lambda x: x * i)
    return multipliers


def create_validators(rules):
    """Create validator functions from a list of rules."""
    validators = {}
    for rule in rules:
        field = rule["field"]
        min_val = rule.get("min", 0)
        max_val = rule.get("max", float("inf"))

        # Bug: same closure issue — field, min_val, max_val captured by reference
        def validate(value):
            if value < min_val or value > max_val:
                return f"{field} must be between {min_val} and {max_val}"
            return None

        validators[field] = validate

    return validators


def main():
    # Test 1: Multipliers
    mults = create_multipliers()
    results = [m(10) for m in mults]
    print(f"Multiplier results: {results}")
    # Expected: [0, 10, 20, 30, 40]
    # Actual: [40, 40, 40, 40, 40] (all use i=4)

    # Test 2: Validators
    rules = [
        {"field": "age", "min": 0, "max": 150},
        {"field": "score", "min": 0, "max": 100},
        {"field": "temperature", "min": -40, "max": 60},
    ]
    validators = create_validators(rules)

    # All validators will use the last rule's values
    print(f"Validate age=200: {validators['age'](200)}")
    # Expected: "age must be between 0 and 150"
    # Actual: "temperature must be between -40 and 60"

    print(f"Validate score=50: {validators['score'](50)}")
    # Expected: None (valid)
    # Actual: None (happens to be valid for temp range too)

    print(f"Validate temperature=100: {validators['temperature'](100)}")
    # Expected: "temperature must be between -40 and 60"
    # Actual: "temperature must be between -40 and 60" (correct by coincidence)


if __name__ == "__main__":
    main()
