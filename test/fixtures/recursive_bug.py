"""
Recursive tree traversal with an off-by-one bug.
The bug: depth counting is wrong, causing the tree to be traversed
one level too deep on the left branch.
"""


class TreeNode:
    def __init__(self, val, left=None, right=None):
        self.val = val
        self.left = left
        self.right = right


def max_depth(node, current_depth=0):
    """Calculate max depth of binary tree. Bug: left branch adds depth wrong."""
    if node is None:
        return current_depth

    # Bug: left uses current_depth + 1 but right uses current_depth
    # This causes asymmetric depth calculation
    left_depth = max_depth(node.left, current_depth + 1)
    right_depth = max_depth(node.right, current_depth)  # Bug! Should be current_depth + 1

    return max(left_depth, right_depth)


def find_path(node, target, path=None):
    """Find path from root to a target value."""
    if path is None:
        path = []

    if node is None:
        return None

    path.append(node.val)

    if node.val == target:
        return path

    left_result = find_path(node.left, target, path)
    if left_result:
        return left_result

    right_result = find_path(node.right, target, path)
    if right_result:
        return right_result

    path.pop()  # Backtrack
    return None


def main():
    #       1
    #      / \
    #     2   3
    #    / \
    #   4   5
    tree = TreeNode(1,
        TreeNode(2,
            TreeNode(4),
            TreeNode(5)),
        TreeNode(3))

    depth = max_depth(tree)
    print(f"Max depth: {depth}")  # Expected: 3, Actual: 2 (right branch not counted)

    path = find_path(tree, 5)
    print(f"Path to 5: {path}")  # Expected: [1, 2, 5]


if __name__ == "__main__":
    main()
