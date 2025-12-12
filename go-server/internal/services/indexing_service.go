package services

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/bilibili/look-alike/internal/database"
	"github.com/bilibili/look-alike/internal/image"
	"github.com/bilibili/look-alike/internal/models"
)

var supportedExtensions = []string{".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tiff", ".tif"}

// IndexingService handles indexing of source and target files
type IndexingService struct {
	project *models.Project
}

// NewIndexingService creates a new indexing service
func NewIndexingService(project *models.Project) *IndexingService {
	return &IndexingService{
		project: project,
	}
}

// Process runs the indexing process
func Process(project *models.Project) error {
	log.Printf("========================================")
	log.Printf("IndexingService.Process started")
	log.Printf("Project: %s (ID: %d)", project.Name, project.ID)
	log.Printf("Source path: %s", project.SourcePath)
	log.Printf("========================================")

	// Update project status
	if err := database.DB.Model(&project).Update("status", "indexing").Error; err != nil {
		return err
	}

	svc := NewIndexingService(project)

	// Index source files
	if err := svc.indexSourceFiles(); err != nil {
		database.DB.Model(&project).Updates(map[string]interface{}{
			"status":        "error",
			"error_message": err.Error(),
		})
		return fmt.Errorf("failed to index source files: %w", err)
	}

	// Index target files
	if err := svc.indexTargetFiles(); err != nil {
		database.DB.Model(&project).Updates(map[string]interface{}{
			"status":        "error",
			"error_message": err.Error(),
		})
		return fmt.Errorf("failed to index target files: %w", err)
	}

	// Update project status to indexed
	if err := database.DB.Model(&project).Update("status", "indexed").Error; err != nil {
		return err
	}

	log.Println("[SUCCESS] IndexingService completed")
	log.Println("========================================")
	return nil
}

// indexSourceFiles indexes all source files
func (svc *IndexingService) indexSourceFiles() error {
	log.Printf("[SOURCE] Scanning source directory: %s", svc.project.SourcePath)

	sourcePath := strings.TrimSpace(svc.project.SourcePath)
	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		return fmt.Errorf("source path does not exist: %s", sourcePath)
	}

	// Find all image files
	images, err := findImages(sourcePath)
	if err != nil {
		return err
	}

	log.Printf("[SOURCE] Found %d source images", len(images))

	if len(images) == 0 {
		return fmt.Errorf("no source images found in: %s", sourcePath)
	}

	// Get existing files to avoid duplicates
	var existingFiles []models.SourceFile
	database.DB.Where("project_id = ?", svc.project.ID).Select("relative_path").Find(&existingFiles)
	existingPaths := make(map[string]bool)
	for _, f := range existingFiles {
		existingPaths[f.RelativePath] = true
	}

	// Filter new images
	var newImages []string
	for _, imgPath := range images {
		relPath, _ := filepath.Rel(sourcePath, imgPath)
		if !existingPaths[relPath] {
			newImages = append(newImages, imgPath)
		}
	}

	log.Printf("[SOURCE] %d new source images to process", len(newImages))

	// Process images concurrently
	var wg sync.WaitGroup
	semaphore := make(chan struct{}, 4) // Limit to 4 concurrent goroutines
	var mu sync.Mutex
	var batch []models.SourceFile
	const batchSize = 100

	for _, imgPath := range newImages {
		wg.Add(1)
		go func(path string) {
			defer wg.Done()
			semaphore <- struct{}{} // Acquire
			defer func() { <-semaphore }() // Release

			sourceFile, err := processSourceFile(path, sourcePath, svc.project.ID)
			if err != nil {
				log.Printf("[ERROR] Failed to process source file %s: %v", path, err)
				return
			}

			mu.Lock()
			batch = append(batch, *sourceFile)
			if len(batch) >= batchSize {
				if err := database.DB.Create(&batch).Error; err != nil {
					log.Printf("[ERROR] Failed to batch insert source files: %v", err)
				} else {
					log.Printf("[SOURCE] Batch inserted %d source files", len(batch))
				}
				batch = nil
			}
			mu.Unlock()
		}(imgPath)
	}

	wg.Wait()

	// Insert remaining batch
	if len(batch) > 0 {
		if err := database.DB.Create(&batch).Error; err != nil {
			return fmt.Errorf("failed to insert remaining source files: %w", err)
		}
		log.Printf("[SOURCE] Inserted final batch of %d source files", len(batch))
	}

	log.Println("[SOURCE] Source file indexing completed")
	return nil
}

// indexTargetFiles indexes all target files
func (svc *IndexingService) indexTargetFiles() error {
	var targets []models.ProjectTarget
	if err := database.DB.Where("project_id = ?", svc.project.ID).Find(&targets).Error; err != nil {
		return err
	}

	log.Printf("[TARGET] Indexing %d target directories", len(targets))

	for _, target := range targets {
		if err := svc.indexSingleTarget(&target); err != nil {
			log.Printf("[ERROR] Failed to index target %s: %v", target.Name, err)
			continue
		}
	}

	log.Println("[TARGET] Target file indexing completed")
	return nil
}

// indexSingleTarget indexes files for a single target
func (svc *IndexingService) indexSingleTarget(target *models.ProjectTarget) error {
	log.Printf("[TARGET] Indexing target: %s (%s)", target.Name, target.Path)

	targetPath := strings.TrimSpace(target.Path)
	if _, err := os.Stat(targetPath); os.IsNotExist(err) {
		return fmt.Errorf("target path does not exist: %s", targetPath)
	}

	images, err := findImages(targetPath)
	if err != nil {
		return err
	}

	log.Printf("[TARGET] Found %d images in target %s", len(images), target.Name)

	// Get existing files
	var existingFiles []models.TargetFile
	database.DB.Where("project_target_id = ?", target.ID).Select("relative_path").Find(&existingFiles)
	existingPaths := make(map[string]bool)
	for _, f := range existingFiles {
		existingPaths[f.RelativePath] = true
	}

	// Filter new images
	var newImages []string
	for _, imgPath := range images {
		relPath, _ := filepath.Rel(targetPath, imgPath)
		if !existingPaths[relPath] {
			newImages = append(newImages, imgPath)
		}
	}

	log.Printf("[TARGET] %d new images to process for target %s", len(newImages), target.Name)

	// Process concurrently
	var wg sync.WaitGroup
	semaphore := make(chan struct{}, 4)
	var mu sync.Mutex
	var batch []models.TargetFile
	const batchSize = 100

	for _, imgPath := range newImages {
		wg.Add(1)
		go func(path string) {
			defer wg.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			targetFile, err := processTargetFile(path, targetPath, target.ID)
			if err != nil {
				log.Printf("[ERROR] Failed to process target file %s: %v", path, err)
				return
			}

			mu.Lock()
			batch = append(batch, *targetFile)
			if len(batch) >= batchSize {
				if err := database.DB.Create(&batch).Error; err != nil {
					log.Printf("[ERROR] Failed to batch insert target files: %v", err)
				} else {
					log.Printf("[TARGET] Batch inserted %d target files", len(batch))
				}
				batch = nil
			}
			mu.Unlock()
		}(imgPath)
	}

	wg.Wait()

	// Insert remaining batch
	if len(batch) > 0 {
		if err := database.DB.Create(&batch).Error; err != nil {
			return fmt.Errorf("failed to insert remaining target files: %w", err)
		}
		log.Printf("[TARGET] Inserted final batch of %d target files", len(batch))
	}

	return nil
}

// processSourceFile processes a single source file
func processSourceFile(fullPath, basePath string, projectID uint) (*models.SourceFile, error) {
	relPath, err := filepath.Rel(basePath, fullPath)
	if err != nil {
		return nil, err
	}

	// Get file info
	fileInfo, err := os.Stat(fullPath)
	if err != nil {
		return nil, err
	}

	// Calculate phash and color histogram
	comparator, err := image.NewImageComparator(fullPath)
	if err != nil {
		return nil, err
	}

	// Convert color histogram to JSON
	histogramJSON, err := json.Marshal(comparator.ColorHistogram)
	if err != nil {
		return nil, err
	}

	// Calculate aspect ratio and area
	aspectRatio := float64(comparator.Width) / float64(comparator.Height)
	area := comparator.Width * comparator.Height

	sourceFile := &models.SourceFile{
		ProjectID:    projectID,
		RelativePath: relPath,
		FullPath:     fullPath,
		Width:        comparator.Width,
		Height:       comparator.Height,
		SizeBytes:    fileInfo.Size(),
		Status:       "indexed",
		AspectRatio:  aspectRatio,
		Area:         area,
		Phash:        fmt.Sprintf("%d", comparator.Phash),
		Ahash:        "", // Not used
		Dhash:        "", // Not used
		Histogram:    string(histogramJSON),
	}

	return sourceFile, nil
}

// processTargetFile processes a single target file
func processTargetFile(fullPath, basePath string, targetID uint) (*models.TargetFile, error) {
	relPath, err := filepath.Rel(basePath, fullPath)
	if err != nil {
		return nil, err
	}

	fileInfo, err := os.Stat(fullPath)
	if err != nil {
		return nil, err
	}

	// Calculate phash and color histogram
	comparator, err := image.NewImageComparator(fullPath)
	if err != nil {
		return nil, err
	}

	// Convert color histogram to JSON
	histogramJSON, err := json.Marshal(comparator.ColorHistogram)
	if err != nil {
		return nil, err
	}

	aspectRatio := float64(comparator.Width) / float64(comparator.Height)
	area := comparator.Width * comparator.Height

	targetFile := &models.TargetFile{
		ProjectTargetID: targetID,
		FullPath:        fullPath,
		RelativePath:    relPath,
		Width:           comparator.Width,
		Height:          comparator.Height,
		SizeBytes:       fileInfo.Size(),
		AspectRatio:     aspectRatio,
		Area:            area,
		Phash:           fmt.Sprintf("%d", comparator.Phash),
		Ahash:           "", // Not used
		Dhash:           "", // Not used
		Histogram:       string(histogramJSON),
	}

	return targetFile, nil
}

// findImages finds all image files in a directory recursively
func findImages(rootPath string) ([]string, error) {
	var images []string

	err := filepath.Walk(rootPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		ext := strings.ToLower(filepath.Ext(path))
		for _, supportedExt := range supportedExtensions {
			if ext == supportedExt {
				images = append(images, path)
				break
			}
		}

		return nil
	})

	return images, err
}
