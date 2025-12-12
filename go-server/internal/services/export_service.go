package services

import (
	"context"
	"encoding/json"
	"fmt"
	"image/color"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"log"
	"os"
	"path/filepath"

	_ "github.com/chai2010/webp"
	"github.com/bilibili/look-alike/internal/database"
	"github.com/bilibili/look-alike/internal/models"
	"github.com/disintegration/imaging"
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
)

// ExportService handles exporting of selected images
type ExportService struct {
	project         *models.Project
	usePlaceholder  bool
	onlyConfirmed   bool
	outputPath      string
	ctx             context.Context
}

// NewExportService creates a new export service
func NewExportService(project *models.Project, usePlaceholder, onlyConfirmed bool, outputPath string, ctx context.Context) *ExportService {
	if ctx == nil {
		ctx = context.Background()
	}
	if outputPath == "" {
		outputPath = filepath.Join(filepath.Dir(project.SourcePath), fmt.Sprintf("%s_Output", project.Name))
	}
	return &ExportService{
		project:        project,
		usePlaceholder: usePlaceholder,
		onlyConfirmed:  onlyConfirmed,
		outputPath:     outputPath,
		ctx:            ctx,
	}
}

// Process runs the export process
func (svc *ExportService) Process() error {
	log.Printf("Starting export for project %s to %s", svc.project.Name, svc.outputPath)

	// Create output directory
	if err := os.MkdirAll(svc.outputPath, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	// Get source files
	query := database.DB.Preload("TargetSelections").
		Preload("TargetSelections.ComparisonCandidate").
		Where("project_id = ?", svc.project.ID)

	if svc.onlyConfirmed {
		query = query.Joins("INNER JOIN source_confirmations ON source_confirmations.source_file_id = source_files.id").
			Where("source_confirmations.confirmed = ?", true)
	}

	var sourceFiles []models.SourceFile
	if err := query.Find(&sourceFiles).Error; err != nil {
		return err
	}

	total := len(sourceFiles)
	log.Printf("Exporting %d source files", total)

	// Write initial progress
	if err := svc.WriteProgress(total, 0, "Starting export..."); err != nil {
		log.Printf("[WARN] Failed to write initial progress: %v", err)
	}

	// If no files to export, mark as completed immediately
	if total == 0 {
		if err := svc.WriteProgress(0, 0, "No files to export"); err != nil {
			log.Printf("[WARN] Failed to write completion progress: %v", err)
		}
		log.Println("Export completed: no files to export")
		return nil
	}

	// Process each source file
	processed := 0
	for _, sf := range sourceFiles {
		select {
		case <-svc.ctx.Done():
			return svc.ctx.Err()
		default:
		}

		if err := svc.exportSourceFile(&sf); err != nil {
			log.Printf("[ERROR] Failed to export %s: %v", sf.RelativePath, err)
			continue
		}

		processed++
		// Update progress
		if err := svc.WriteProgress(total, processed, sf.RelativePath); err != nil {
			log.Printf("[WARN] Failed to write progress: %v", err)
		}
	}

	// Write completion progress
	if err := svc.WriteProgress(total, processed, "Export completed"); err != nil {
		log.Printf("[WARN] Failed to write completion progress: %v", err)
	}

	log.Println("Export completed")
	return nil
}

// exportSourceFile exports a single source file
func (svc *ExportService) exportSourceFile(sf *models.SourceFile) error {
	// Create subdirectory
	relDir := filepath.Dir(sf.RelativePath)
	outputDir := filepath.Join(svc.outputPath, relDir)
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return err
	}

	// Get selected files for all targets
	for _, selection := range sf.TargetSelections {
		var targetPath string
		var targetName string

		if selection.NoMatch {
			if !svc.usePlaceholder {
				continue
			}
			// Create placeholder
			targetName = "no_match_placeholder"
			targetPath = filepath.Join(outputDir, fmt.Sprintf("%s_%s.png", filepath.Base(sf.RelativePath), targetName))
			if err := svc.createPlaceholder(targetPath, sf.Width, sf.Height); err != nil {
				return err
			}
			continue
		}

		if selection.ComparisonCandidate != nil {
			targetPath = selection.ComparisonCandidate.FilePath
			// Get target name
			var target models.ProjectTarget
			database.DB.First(&target, selection.ProjectTargetID)
			targetName = target.Name
		}

		if targetPath == "" {
			continue
		}

		// Create target-specific subdirectory
		targetOutputDir := filepath.Join(outputDir, targetName)
		if err := os.MkdirAll(targetOutputDir, 0755); err != nil {
			return err
		}

		// Use source file name (keep original name, just change extension if needed)
		outputPath := filepath.Join(targetOutputDir, filepath.Base(sf.RelativePath))

		if err := svc.copyAndConvert(targetPath, outputPath, filepath.Ext(sf.RelativePath)); err != nil {
			return err
		}
	}

	return nil
}

// copyAndConvert copies and converts an image file
func (svc *ExportService) copyAndConvert(srcPath, dstPath, targetExt string) error {
	srcExt := filepath.Ext(srcPath)

	// If same extension, just copy
	if srcExt == targetExt {
		return copyFile(srcPath, dstPath)
	}

	// Convert format
	img, err := imaging.Open(srcPath)
	if err != nil {
		return err
	}

	return imaging.Save(img, dstPath)
}

// createPlaceholder creates a placeholder image
func (svc *ExportService) createPlaceholder(path string, width, height int) error {
	// Create a simple gray placeholder
	img := imaging.New(width, height, color.RGBA{128, 128, 128, 255})
	return imaging.Save(img, path)
}

// copyFile copies a file
func copyFile(src, dst string) error {
	input, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, input, 0644)
}

// WriteProgress writes progress information
func (svc *ExportService) WriteProgress(total, processed int, current string) error {
	progressFile := filepath.Join(svc.outputPath, ".export_progress.json")
	progress := map[string]interface{}{
		"total":     total,
		"processed": processed,
		"current":   current,
	}
	data, err := json.Marshal(progress)
	if err != nil {
		return err
	}
	return os.WriteFile(progressFile, data, 0644)
}
