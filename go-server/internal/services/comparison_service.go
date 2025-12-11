package services

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	"github.com/bilibili/look-alike/internal/database"
	"github.com/bilibili/look-alike/internal/image"
	"github.com/bilibili/look-alike/internal/models"
)

const (
	batchSize         = 100
	concurrentWorkers = 4
)

// ComparisonService handles comparison of source and target files
type ComparisonService struct {
	project *models.Project
	ctx     context.Context
}

// NewComparisonService creates a new comparison service
func NewComparisonService(project *models.Project, ctx context.Context) *ComparisonService {
	if ctx == nil {
		ctx = context.Background()
	}
	return &ComparisonService{
		project: project,
		ctx:     ctx,
	}
}

// ProcessComparison runs the comparison process
func ProcessComparison(project *models.Project, ctx context.Context) error {
	log.Println("=========================================")
	log.Printf("ComparisonService.Process started for project %d: %s", project.ID, project.Name)
	log.Printf("Project status: %s", project.Status)
	log.Println("=========================================")

	// Update status to processing
	database.DB.Model(&project).Updates(map[string]interface{}{
		"status":     "processing",
		"started_at": time.Now(),
	})

	// Run indexing first if needed
	if project.Status != "indexed" {
		log.Println("[INDEXING] Starting indexing phase...")
		if err := Process(project); err != nil {
			return err
		}
		log.Println("[INDEXING] Indexing phase completed")
	}

	// Validate indexing
	var totalSourceFiles, indexedSourceFiles, totalTargetFiles int64
	database.DB.Model(&models.SourceFile{}).Where("project_id = ?", project.ID).Count(&totalSourceFiles)
	database.DB.Model(&models.SourceFile{}).Where("project_id = ? AND status = ?", project.ID, "indexed").Count(&indexedSourceFiles)

	database.DB.Table("target_files").
		Joins("INNER JOIN project_targets ON project_targets.id = target_files.project_target_id").
		Where("project_targets.project_id = ?", project.ID).
		Count(&totalTargetFiles)

	log.Println("[VALIDATION] Validating indexing results...")
	log.Printf("[VALIDATION] Total source files: %d", totalSourceFiles)
	log.Printf("[VALIDATION] Indexed source files: %d", indexedSourceFiles)
	log.Printf("[VALIDATION] Total target files: %d", totalTargetFiles)

	if totalSourceFiles == 0 {
		err := fmt.Errorf("no source files found after indexing")
		database.DB.Model(&project).Updates(map[string]interface{}{
			"status":        "error",
			"error_message": err.Error(),
		})
		return err
	}

	if totalTargetFiles == 0 {
		err := fmt.Errorf("no target files found after indexing")
		database.DB.Model(&project).Updates(map[string]interface{}{
			"status":        "error",
			"error_message": err.Error(),
		})
		return err
	}

	// Start comparison phase
	log.Println("[COMPARING] Starting comparison phase...")
	database.DB.Model(&project).Update("status", "comparing")

	svc := NewComparisonService(project, ctx)
	if err := svc.compareAll(); err != nil {
		database.DB.Model(&project).Updates(map[string]interface{}{
			"status":        "error",
			"error_message": err.Error(),
		})
		return err
	}

	// Create auto-selections
	if err := svc.createAutoSelections(); err != nil {
		log.Printf("[WARNING] Failed to create auto-selections: %v", err)
	}

	// Update to completed
	database.DB.Model(&project).Updates(map[string]interface{}{
		"status":   "completed",
		"ended_at": time.Now(),
	})

	log.Println("[SUCCESS] Comparison phase completed")
	log.Println("=========================================")
	return nil
}

// compareAll compares all source files with all targets
func (svc *ComparisonService) compareAll() error {
	// Preload all project targets and their files
	var targets []models.ProjectTarget
	if err := database.DB.Preload("TargetFiles").Where("project_id = ?", svc.project.ID).Find(&targets).Error; err != nil {
		return err
	}

	log.Printf("[COMPARING] Preloaded %d targets", len(targets))

	// Get all indexed source files
	var sourceFiles []models.SourceFile
	if err := database.DB.Where("project_id = ? AND status = ?", svc.project.ID, "indexed").Find(&sourceFiles).Error; err != nil {
		return err
	}

	log.Printf("[COMPARING] Processing %d indexed source files...", len(sourceFiles))

	if len(sourceFiles) == 0 {
		return fmt.Errorf("no indexed source files found")
	}

	// Process concurrently with semaphore
	var wg sync.WaitGroup
	semaphore := make(chan struct{}, concurrentWorkers)
	var mu sync.Mutex
	var candidateBatch []models.ComparisonCandidate
	var updateBatch []uint

	for i := range sourceFiles {
		// Check context cancellation
		select {
		case <-svc.ctx.Done():
			log.Println("[COMPARING] Context cancelled, stopping comparison")
			return svc.ctx.Err()
		default:
		}

		wg.Add(1)
		go func(sf *models.SourceFile) {
			defer wg.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			candidates := svc.compareSingleSource(sf, targets)

			mu.Lock()
			candidateBatch = append(candidateBatch, candidates...)
			updateBatch = append(updateBatch, sf.ID)

			// Batch insert candidates
			if len(candidateBatch) >= batchSize {
				if err := database.DB.Create(&candidateBatch).Error; err != nil {
					log.Printf("[ERROR] Failed to batch insert candidates: %v", err)
				} else {
					log.Printf("[COMPARING] Batch inserted %d candidates", len(candidateBatch))
				}
				candidateBatch = nil
			}

			// Batch update source files
			if len(updateBatch) >= batchSize {
				database.DB.Model(&models.SourceFile{}).Where("id IN ?", updateBatch).Update("status", "analyzed")
				log.Printf("[COMPARING] Batch updated %d source files to analyzed", len(updateBatch))
				updateBatch = nil
			}
			mu.Unlock()
		}(&sourceFiles[i])
	}

	wg.Wait()

	// Insert remaining batches
	if len(candidateBatch) > 0 {
		if err := database.DB.Create(&candidateBatch).Error; err != nil {
			return fmt.Errorf("failed to insert remaining candidates: %w", err)
		}
		log.Printf("[COMPARING] Inserted final batch of %d candidates", len(candidateBatch))
	}

	if len(updateBatch) > 0 {
		database.DB.Model(&models.SourceFile{}).Where("id IN ?", updateBatch).Update("status", "analyzed")
		log.Printf("[COMPARING] Updated final batch of %d source files", len(updateBatch))
	}

	return nil
}

// compareSingleSource compares a single source file with all targets
func (svc *ComparisonService) compareSingleSource(sourceFile *models.SourceFile, targets []models.ProjectTarget) []models.ComparisonCandidate {
	var allCandidates []models.ComparisonCandidate

	for _, target := range targets {
		// Compare with all target files (no dimension filtering)
		log.Printf("Source %s: comparing with %d targets for target %s",
			sourceFile.RelativePath, len(target.TargetFiles), target.Name)

		// Calculate similarities with all targets
		candidates := svc.calculateSimilarities(sourceFile, target.TargetFiles, target.ID)

		// Apply adaptive threshold
		finalCandidates := svc.applyAdaptiveThreshold(candidates, sourceFile.ID, sourceFile.RelativePath, target.Name)

		allCandidates = append(allCandidates, finalCandidates...)
	}

	return allCandidates
}

// calculateSimilarities calculates similarity scores
func (svc *ComparisonService) calculateSimilarities(sourceFile *models.SourceFile, targetFiles []models.TargetFile, targetID uint) []candidateScore {
	var candidates []candidateScore

	for _, tf := range targetFiles {
		similarity := calculateSimilarityFromHashes(sourceFile, &tf)
		candidates = append(candidates, candidateScore{
			targetFile: &tf,
			similarity: similarity,
		})
	}

	return candidates
}

type candidateScore struct {
	targetFile *models.TargetFile
	similarity float64
}

// applyAdaptiveThreshold applies adaptive thresholding
func (svc *ComparisonService) applyAdaptiveThreshold(candidates []candidateScore, sourceFileID uint, sourcePath, targetName string) []models.ComparisonCandidate {
	if len(candidates) == 0 {
		return nil
	}

	// Sort by similarity descending
	for i := 0; i < len(candidates)-1; i++ {
		for j := i + 1; j < len(candidates); j++ {
			if candidates[j].similarity > candidates[i].similarity {
				candidates[i], candidates[j] = candidates[j], candidates[i]
			}
		}
	}

	// Try different thresholds
	thresholds := []float64{50.0, 40.0, 30.0, 20.0, 10.0, 0.0}
	var finalCandidates []candidateScore

	for _, threshold := range thresholds {
		filtered := []candidateScore{}
		for _, c := range candidates {
			if c.similarity > threshold {
				filtered = append(filtered, c)
			}
		}

		if len(filtered) > 0 {
			// Limit to 50 candidates
			if len(filtered) > 50 {
				filtered = filtered[:50]
			}
			finalCandidates = filtered
			break
		}
	}

	// Force select top candidate if none found
	if len(finalCandidates) == 0 && len(candidates) > 0 {
		finalCandidates = []candidateScore{candidates[0]}
		log.Printf("  Forced selection of highest similarity candidate: %.2f%%", candidates[0].similarity)
	}

	// Convert to ComparisonCandidate models
	var result []models.ComparisonCandidate
	for i, c := range finalCandidates {
		result = append(result, models.ComparisonCandidate{
			SourceFileID:    sourceFileID,
			ProjectTargetID: c.targetFile.ProjectTargetID,
			FilePath:        c.targetFile.FullPath,
			SimilarityScore: c.similarity,
			Rank:            i + 1,
			Width:           c.targetFile.Width,
			Height:          c.targetFile.Height,
		})
	}

	log.Printf("Found %d candidates for %s in %s", len(result), sourcePath, targetName)
	return result
}

// calculateSimilarityFromHashes calculates similarity using pre-computed phash only
func calculateSimilarityFromHashes(source *models.SourceFile, target *models.TargetFile) float64 {
	// Parse phash from strings
	sourcePhash, _ := strconv.ParseUint(source.Phash, 10, 64)
	targetPhash, _ := strconv.ParseUint(target.Phash, 10, 64)

	// Calculate phash similarity
	phashSim := image.HashSimilarity(sourcePhash, targetPhash, 64)

	return phashSim
}

// createAutoSelections creates default selections for rank 1 candidates
func (svc *ComparisonService) createAutoSelections() error {
	log.Println("Creating auto-selections for best matches...")

	var bestCandidates []models.ComparisonCandidate
	database.DB.Where("rank = ?", 1).
		Joins("INNER JOIN source_files ON source_files.id = comparison_candidates.source_file_id").
		Where("source_files.project_id = ?", svc.project.ID).
		Find(&bestCandidates)

	var selections []models.TargetSelection
	for _, candidate := range bestCandidates {
		selections = append(selections, models.TargetSelection{
			SourceFileID:        candidate.SourceFileID,
			ProjectTargetID:     candidate.ProjectTargetID,
			SelectedCandidateID: &candidate.ID,
			NoMatch:             false,
		})

		if len(selections) >= batchSize {
			if err := database.DB.Create(&selections).Error; err != nil {
				log.Printf("[ERROR] Failed to batch insert selections: %v", err)
			} else {
				log.Printf("Batch inserted %d auto-selections", len(selections))
			}
			selections = nil
		}
	}

	if len(selections) > 0 {
		if err := database.DB.Create(&selections).Error; err != nil {
			return err
		}
		log.Printf("Inserted final %d auto-selections", len(selections))
	}

	log.Println("Auto-selection completed")
	return nil
}
