/**
 * A script with a subtle bug: processes user records and calculates average age.
 * The bug: one record has age as a string instead of int, causing wrong average.
 */

function loadUsers() {
  return [
    { name: "Alice", age: 30, active: true },
    { name: "Bob", age: 25, active: true },
    { name: "Charlie", age: "35", active: true },  // Bug: age is string "35"
    { name: "Diana", age: 28, active: false },
    { name: "Eve", age: 32, active: true },
  ];
}

function calculateAverageAge(users) {
  const activeUsers = users.filter(u => u.active);
  let total = 0;
  let count = 0;
  for (const user of activeUsers) {
    const data = user;
    total += data.age;  // This will concatenate string instead of add
    count += 1;
  }
  return count > 0 ? total / count : 0;
}

function main() {
  const users = loadUsers();
  const avg = calculateAverageAge(users);
  console.log(`Average age of active users: ${avg}`);
  // Expected: (30 + 25 + 35 + 32) / 4 = 30.5
  // Actual: will give wrong result because "35" is a string
}

main();
