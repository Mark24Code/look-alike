package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/bilibili/look-alike/internal/api"
	"github.com/bilibili/look-alike/internal/database"
)

func main() {
	log.Println("========================================")
	log.Println("Look-Alike Server (Go Version)")
	log.Println("========================================")

	// Get executable directory or current working directory
	exePath, err := os.Executable()
	var baseDir string
	if err == nil {
		baseDir = filepath.Dir(exePath)
	} else {
		baseDir, _ = os.Getwd()
	}

	// Database path - check multiple locations
	dbPath := filepath.Join(baseDir, "db/look_alike.sqlite3")
	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		// Try relative to working directory
		dbPath = "db/look_alike.sqlite3"
	}
	log.Printf("Database path: %s", dbPath)

	// Initialize database
	if err := database.Initialize(dbPath); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	// Client dist path (for production mode)
	clientDistPath := filepath.Join(baseDir, "client/dist")
	if _, err := os.Stat(filepath.Join(clientDistPath, "index.html")); os.IsNotExist(err) {
		// Try relative to working directory
		clientDistPath = "client/dist"
		if _, err := os.Stat(filepath.Join(clientDistPath, "index.html")); os.IsNotExist(err) {
			log.Println("Warning: Frontend dist not found, running in API-only mode")
			clientDistPath = ""
		}
	}

	// Setup router
	router := api.SetupRouter(clientDistPath)

	// Start server
	port := "4568"
	if envPort := os.Getenv("PORT"); envPort != "" {
		port = envPort
	}

	log.Println("========================================")
	log.Printf("Server starting on http://0.0.0.0:%s", port)
	log.Printf("API endpoint: http://localhost:%s/api/health", port)
	if clientDistPath != "" {
		log.Printf("Frontend: http://localhost:%s", port)
	}
	log.Println("========================================")

	if err := router.Run(fmt.Sprintf("0.0.0.0:%s", port)); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
