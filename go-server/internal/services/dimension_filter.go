package services

import (
	"math"

	"github.com/bilibili/look-alike/internal/models"
)

// DimensionFilter provides adaptive filtering of target files based on dimensions
type DimensionFilter struct{}

// AdaptiveFilterTargets filters target files based on source file dimensions
// Uses progressive tolerance levels to ensure at least some candidates
func AdaptiveFilterTargets(sourceFile *models.SourceFile, allTargets []models.TargetFile) []models.TargetFile {
	tolerances := []float64{0.10, 0.15, 0.20, 0.30} // 10%, 15%, 20%, 30%

	for _, tolerance := range tolerances {
		candidates := filterByDimensions(sourceFile, allTargets, tolerance)
		if len(candidates) > 0 {
			return candidates
		}
	}

	// If all tolerances fail, return all targets (no filtering)
	return allTargets
}

// filterByDimensions filters targets within tolerance range
func filterByDimensions(sourceFile *models.SourceFile, targets []models.TargetFile, tolerance float64) []models.TargetFile {
	var filtered []models.TargetFile

	for _, target := range targets {
		if matchesDimensions(sourceFile, &target, tolerance) {
			filtered = append(filtered, target)
		}
	}

	return filtered
}

// matchesDimensions checks if dimensions match within tolerance
func matchesDimensions(source *models.SourceFile, target *models.TargetFile, tolerance float64) bool {
	// File size match
	if !matchesFileSize(source.SizeBytes, target.SizeBytes, tolerance) {
		return false
	}

	// Dimension match
	if !matchesSize(source.Width, target.Width, tolerance) {
		return false
	}
	if !matchesSize(source.Height, target.Height, tolerance) {
		return false
	}

	return true
}

// matchesFileSize checks if file sizes match within tolerance
func matchesFileSize(size1, size2 int64, tolerance float64) bool {
	if size1 == 0 || size2 == 0 {
		return false
	}

	ratio := math.Abs(float64(size1) / float64(size2))
	return ratio >= (1.0-tolerance) && ratio <= (1.0+tolerance)
}

// matchesSize checks if dimensions match within tolerance
func matchesSize(size1, size2 int, tolerance float64) bool {
	if size1 == 0 || size2 == 0 {
		return false
	}

	ratio := math.Abs(float64(size1) / float64(size2))
	return ratio >= (1.0-tolerance) && ratio <= (1.0+tolerance)
}
