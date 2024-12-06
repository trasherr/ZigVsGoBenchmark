package main

import (
	"database/sql"
	"log"
	"net/http"

	_ "github.com/mattn/go-sqlite3"
)

var db *sql.DB
var userModel *UserModel

func main() {
	var err error
	// Connect to the SQLite database
	db, err = sql.Open("sqlite3", "./benchmark.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Create the users table if it doesn't exist
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT,
		email TEXT UNIQUE,
		age INTEGER,
		password TEXT
	)`)
	if err != nil {
		log.Fatal(err)
	}

	userModel = &UserModel{DB: db}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", getAllUsers)
	mux.HandleFunc("GET /user", login)
	mux.HandleFunc("POST /user", register)
	mux.HandleFunc("PUT /user", authMiddleware(updateUser))
	mux.HandleFunc("DELETE /user", authMiddleware(deleteUser))

	http.ListenAndServe("localhost:3000", mux)
}