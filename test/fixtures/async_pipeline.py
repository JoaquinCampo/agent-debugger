"""
Data pipeline with multiple transformation stages.
Bug: a filter stage silently drops valid records due to
a type comparison issue, and the aggregation uses wrong keys.
"""

import json
from collections import defaultdict


def load_records():
    """Simulate loading records from a JSON source."""
    raw = [
        {"id": 1, "category": "electronics", "price": 299.99, "quantity": 2, "status": "active"},
        {"id": 2, "category": "books", "price": 15.50, "quantity": "5", "status": "active"},  # Bug: quantity is str
        {"id": 3, "category": "electronics", "price": 149.99, "quantity": 1, "status": "inactive"},
        {"id": 4, "category": "clothing", "price": 45.00, "quantity": 3, "status": "active"},
        {"id": 5, "category": "electronics", "price": 999.99, "quantity": 1, "status": "active"},
        {"id": 6, "category": "books", "price": 22.00, "quantity": 4, "status": "active"},
        {"id": 7, "category": "clothing", "price": 89.99, "quantity": 0, "status": "active"},  # Zero quantity
    ]
    return raw


def filter_active(records):
    """Filter to only active records with positive quantity."""
    result = []
    for r in records:
        if r["status"] == "active" and r["quantity"] > 0:  # Bug: str "5" > 0 is True in Py, but str comparison
            result.append(r)
    return result


def calculate_totals(records):
    """Calculate total value per category."""
    totals = defaultdict(lambda: {"total_value": 0, "item_count": 0})

    for r in records:
        cat = r["category"]
        # Bug: quantity might be string, price * "5" gives wrong result
        value = r["price"] * r["quantity"]
        totals[cat]["total_value"] += value
        totals[cat]["item_count"] += 1

    return dict(totals)


def format_report(totals):
    """Format totals into a report."""
    lines = ["=== Sales Report ==="]
    grand_total = 0
    for cat, data in sorted(totals.items()):
        lines.append(f"  {cat}: ${data['total_value']:.2f} ({data['item_count']} items)")
        grand_total += data["total_value"]
    lines.append(f"  Grand Total: ${grand_total:.2f}")
    return "\n".join(lines)


def main():
    records = load_records()
    active = filter_active(records)
    totals = calculate_totals(active)
    report = format_report(totals)
    print(report)

    # Expected for active records with quantity > 0:
    # electronics: 299.99*2 + 999.99*1 = 1599.97 (2 items)
    # books: 15.50*5 + 22.00*4 = 165.50 (2 items)
    # clothing: 45.00*3 = 135.00 (1 item, id=7 has qty 0)
    # Grand total: 1900.47


if __name__ == "__main__":
    main()
