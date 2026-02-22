"""
Class hierarchy with method resolution order bugs.
The bug: a subclass overrides a method but calls super() wrong,
leading to incorrect state accumulation.
"""


class EventProcessor:
    def __init__(self):
        self.events = []
        self.processed_count = 0

    def process(self, event):
        """Base processing: validate and store."""
        if not isinstance(event, dict):
            raise ValueError(f"Expected dict, got {type(event).__name__}")
        if "type" not in event:
            raise ValueError("Event missing 'type' field")
        self.events.append(event)
        self.processed_count += 1
        return {"status": "processed", "id": self.processed_count}


class FilteringProcessor(EventProcessor):
    def __init__(self, allowed_types):
        super().__init__()
        self.allowed_types = allowed_types
        self.filtered_count = 0

    def process(self, event):
        """Filter events by type before processing."""
        if event.get("type") not in self.allowed_types:
            self.filtered_count += 1
            return {"status": "filtered", "type": event.get("type")}
        return super().process(event)


class TransformingProcessor(FilteringProcessor):
    def __init__(self, allowed_types, transform_fn):
        super().__init__(allowed_types)
        self.transform_fn = transform_fn
        self.transform_errors = []

    def process(self, event):
        """Transform event data before filtering and processing."""
        try:
            transformed = self.transform_fn(event)
        except Exception as e:
            self.transform_errors.append({"event": event, "error": str(e)})
            # Bug: still calls super().process() with the ORIGINAL event, not transformed
            return super().process(event)

        # Bug: this should be super().process(transformed), but uses event
        result = super().process(event)  # Passes original, not transformed!
        result["transformed"] = True
        return result


def enrich_event(event):
    """Add timestamp and normalize the data field."""
    enriched = dict(event)
    enriched["timestamp"] = "2024-01-15T10:30:00Z"
    if "data" in enriched and isinstance(enriched["data"], str):
        enriched["data"] = enriched["data"].upper()
    return enriched


def main():
    processor = TransformingProcessor(
        allowed_types=["click", "view", "purchase"],
        transform_fn=enrich_event,
    )

    events = [
        {"type": "click", "data": "button_submit", "page": "/checkout"},
        {"type": "view", "data": "product_page", "page": "/products/123"},
        {"type": "hover", "data": "menu_item"},  # Should be filtered
        {"type": "purchase", "data": "order_456", "amount": 99.99},
        {"type": "click", "data": 12345},  # data is int, not str — transform should handle
    ]

    results = []
    for event in events:
        result = processor.process(event)
        results.append(result)

    print(f"Results: {results}")
    print(f"Processed: {processor.processed_count}")
    print(f"Filtered: {processor.filtered_count}")
    print(f"Transform errors: {processor.transform_errors}")
    print(f"Stored events: {processor.events}")

    # Bug evidence: stored events have original data, not transformed
    # e.g., events[0]["data"] == "button_submit" instead of "BUTTON_SUBMIT"


if __name__ == "__main__":
    main()
