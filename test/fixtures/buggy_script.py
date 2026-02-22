"""
A script with a subtle bug: processes user records and calculates average age.
The bug: one record has age as a string instead of int, causing wrong average.
"""


def load_users():
    """Simulate loading user data from a database/API."""
    return [
        {"name": "Alice", "age": 30, "active": True},
        {"name": "Bob", "age": 25, "active": True},
        {"name": "Charlie", "age": "35", "active": True},  # Bug: age is string "35"
        {"name": "Diana", "age": 28, "active": False},
        {"name": "Eve", "age": 32, "active": True},
    ]


def calculate_average_age(users):
    """Calculate average age of active users."""
    active_users = [u for u in users if u["active"]]
    total = 0
    count = 0
    for user in active_users:
        data = user
        total += data["age"]  # This will concatenate string instead of add
        count += 1
    return total / count if count > 0 else 0


def main():
    users = load_users()
    avg = calculate_average_age(users)
    print(f"Average age of active users: {avg}")
    # Expected: (30 + 25 + 35 + 32) / 4 = 30.5
    # Actual: will fail or give wrong result because "35" is a string


if __name__ == "__main__":
    main()
