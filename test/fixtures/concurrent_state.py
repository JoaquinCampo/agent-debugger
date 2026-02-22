"""
Simulated concurrent state management bug.
No actual threading — simulates the logical bug of shared mutable state
where operations interleave incorrectly.
"""


class Account:
    def __init__(self, name, balance):
        self.name = name
        self.balance = balance
        self.transaction_log = []

    def deposit(self, amount):
        old_balance = self.balance
        self.balance += amount
        self.transaction_log.append({
            "type": "deposit",
            "amount": amount,
            "old_balance": old_balance,
            "new_balance": self.balance,
        })

    def withdraw(self, amount):
        old_balance = self.balance
        if self.balance >= amount:
            self.balance -= amount
            self.transaction_log.append({
                "type": "withdraw",
                "amount": amount,
                "old_balance": old_balance,
                "new_balance": self.balance,
                "success": True,
            })
            return True
        self.transaction_log.append({
            "type": "withdraw",
            "amount": amount,
            "old_balance": old_balance,
            "new_balance": self.balance,
            "success": False,
        })
        return False


class TransferService:
    def __init__(self):
        self.transfer_log = []

    def transfer(self, from_account, to_account, amount):
        """Transfer money between accounts.
        Bug: doesn't check balance atomically — reads balance, then acts on stale data.
        """
        # Bug: balance check is separate from withdrawal
        # In concurrent scenario, another transfer could drain the account between
        # the check and the withdrawal
        if from_account.balance < amount:
            self.transfer_log.append({
                "from": from_account.name,
                "to": to_account.name,
                "amount": amount,
                "success": False,
                "reason": "insufficient_funds",
            })
            return False

        # Simulate "another transfer happens here" by processing pending ops
        from_account.withdraw(amount)
        to_account.deposit(amount)
        self.transfer_log.append({
            "from": from_account.name,
            "to": to_account.name,
            "amount": amount,
            "success": True,
        })
        return True


def simulate_race_condition():
    """Simulate what happens when two transfers share the same source account."""
    alice = Account("Alice", 100)
    bob = Account("Bob", 50)
    charlie = Account("Charlie", 0)

    service = TransferService()

    # Two "concurrent" transfers from Alice
    # Alice has $100, both transfers are for $75
    # Only one should succeed, but the bug lets both pass the balance check

    # Transfer 1: check passes (100 >= 75)
    can_transfer_1 = alice.balance >= 75  # True

    # Transfer 2: check passes (100 >= 75) — hasn't been debited yet!
    can_transfer_2 = alice.balance >= 75  # True — BUG: stale read

    # Now both proceed
    if can_transfer_1:
        service.transfer(alice, bob, 75)
    if can_transfer_2:
        service.transfer(alice, charlie, 75)  # This should fail but succeeds

    print(f"Alice balance: ${alice.balance}")   # Expected: >= 0, Actual: -$50
    print(f"Bob balance: ${bob.balance}")       # $125
    print(f"Charlie balance: ${charlie.balance}")  # $75
    print(f"Transfer log: {service.transfer_log}")

    # The invariant violation: total money changed
    total = alice.balance + bob.balance + charlie.balance
    initial_total = 100 + 50 + 0  # $150
    print(f"Total money: ${total} (should be ${initial_total})")

    return alice.balance >= 0  # Should be True, but is False


def main():
    ok = simulate_race_condition()
    if not ok:
        print("\nBUG DETECTED: Account went negative!")
    else:
        print("\nAll accounts valid.")


if __name__ == "__main__":
    main()
