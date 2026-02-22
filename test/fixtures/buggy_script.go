package main

import "fmt"

type User struct {
	Name   string
	Age    int
	Active bool
}

func loadUsers() []User {
	return []User{
		{Name: "Alice", Age: 30, Active: true},
		{Name: "Bob", Age: 25, Active: true},
		{Name: "Charlie", Age: 35, Active: true},
		{Name: "Diana", Age: 28, Active: false},
		{Name: "Eve", Age: 32, Active: true},
	}
}

func calculateAverageAge(users []User) float64 {
	total := 0
	count := 0
	for _, user := range users {
		if user.Active {
			total += user.Age
			count++
		}
	}
	if count == 0 {
		return 0
	}
	return float64(total) / float64(count)
}

func main() {
	users := loadUsers()
	avg := calculateAverageAge(users)
	fmt.Printf("Average age of active users: %.1f\n", avg)
}
