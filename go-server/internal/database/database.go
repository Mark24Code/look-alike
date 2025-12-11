package database

import (
	"fmt"
	"log"

	"github.com/bilibili/look-alike/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// Initialize initializes the database connection
func Initialize(dbPath string) error {
	var err error
	DB, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent), // Can be changed to logger.Info for debugging
	})
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	// Get underlying SQL DB to configure connection pool
	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get database instance: %w", err)
	}

	// Configure SQLite for better concurrency (WAL mode)
	if err := DB.Exec("PRAGMA journal_mode=WAL;").Error; err != nil {
		return fmt.Errorf("failed to set WAL mode: %w", err)
	}
	if err := DB.Exec("PRAGMA synchronous=NORMAL;").Error; err != nil {
		return fmt.Errorf("failed to set synchronous mode: %w", err)
	}

	// Configure connection pool
	sqlDB.SetMaxOpenConns(10)
	sqlDB.SetMaxIdleConns(5)

	// Auto-migrate database schema
	if err := autoMigrate(); err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	log.Println("SQLite database initialized with WAL mode")
	return nil
}

// autoMigrate creates or updates database tables
func autoMigrate() error {
	return DB.AutoMigrate(
		&models.Project{},
		&models.ProjectTarget{},
		&models.SourceFile{},
		&models.TargetFile{},
		&models.ComparisonCandidate{},
		&models.TargetSelection{},
		&models.SourceConfirmation{},
	)
}

// Close closes the database connection
func Close() error {
	sqlDB, err := DB.DB()
	if err != nil {
		return err
	}
	return sqlDB.Close()
}
