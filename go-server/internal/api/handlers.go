package api

import (
	"context"
	"log"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/bilibili/look-alike/internal/database"
	"github.com/bilibili/look-alike/internal/models"
	"github.com/bilibili/look-alike/internal/services"
	"github.com/bilibili/look-alike/internal/workers"
	"github.com/gin-gonic/gin"
)

// GetProjects returns list of projects with pagination
func GetProjects(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	perPage := 20

	var projects []models.Project
	var total int64

	database.DB.Model(&models.Project{}).Count(&total)
	database.DB.Order("created_at DESC").Limit(perPage).Offset((page - 1) * perPage).Find(&projects)

	// Add statistics for each project
	var projectsWithStats []map[string]interface{}
	for _, project := range projects {
		var totalFiles, confirmedFiles int64
		database.DB.Model(&models.SourceFile{}).Where("project_id = ?", project.ID).Count(&totalFiles)
		database.DB.Table("source_files").
			Joins("INNER JOIN source_confirmations ON source_confirmations.source_file_id = source_files.id").
			Where("source_files.project_id = ? AND source_confirmations.confirmed = ?", project.ID, true).
			Count(&confirmedFiles)

		projectData := map[string]interface{}{
			"id":           project.ID,
			"name":         project.Name,
			"source_path":  project.SourcePath,
			"status":       project.Status,
			"started_at":   project.StartedAt,
			"ended_at":     project.EndedAt,
			"created_at":   project.CreatedAt,
			"updated_at":   project.UpdatedAt,
			"output_path":  filepath.Join(filepath.Dir(project.SourcePath), project.Name+"_Output"),
			"confirmation_stats": map[string]interface{}{
				"confirmed": confirmedFiles,
				"total":     totalFiles,
			},
		}
		projectsWithStats = append(projectsWithStats, projectData)
	}

	c.JSON(http.StatusOK, gin.H{
		"projects": projectsWithStats,
		"total":    total,
		"page":     page,
		"per_page": perPage,
	})
}

// CreateProject creates a new project
func CreateProject(c *gin.Context) {
	var req struct {
		Name       string `json:"name" binding:"required"`
		SourcePath string `json:"source_path" binding:"required"`
		Targets    []struct {
			Name string `json:"name"`
			Path string `json:"path"`
		} `json:"targets"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	project := models.Project{
		Name:       req.Name,
		SourcePath: req.SourcePath,
		Status:     "pending",
	}

	if err := database.DB.Create(&project).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Create targets
	for _, t := range req.Targets {
		target := models.ProjectTarget{
			ProjectID: project.ID,
			Name:      t.Name,
			Path:      t.Path,
		}
		database.DB.Create(&target)
	}

	// Start background comparison
	manager := workers.GetManager()
	manager.StartComparison(project.ID, func(ctx context.Context) {
		if err := services.ProcessComparison(&project, ctx); err != nil {
			log.Printf("Comparison failed for project %d: %v", project.ID, err)
		}
	})

	c.JSON(http.StatusOK, project)
}

// GetProject returns a single project
func GetProject(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var project models.Project
	if err := database.DB.First(&project, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Project not found"})
		return
	}

	// Get targets
	var targets []models.ProjectTarget
	database.DB.Where("project_id = ?", project.ID).Find(&targets)

	// Progress stats
	var totalFiles, processed int64
	database.DB.Model(&models.SourceFile{}).Where("project_id = ?", project.ID).Count(&totalFiles)
	database.DB.Model(&models.SourceFile{}).Where("project_id = ? AND status = ?", project.ID, "analyzed").Count(&processed)

	progress := float64(0)
	if totalFiles > 0 {
		progress = float64(processed) / float64(totalFiles) * 100
	}

	c.JSON(http.StatusOK, gin.H{
		"id":           project.ID,
		"name":         project.Name,
		"source_path":  project.SourcePath,
		"status":       project.Status,
		"error_message": project.ErrorMessage,
		"started_at":   project.StartedAt,
		"ended_at":     project.EndedAt,
		"created_at":   project.CreatedAt,
		"updated_at":   project.UpdatedAt,
		"stats": gin.H{
			"total_files": totalFiles,
			"processed":   processed,
			"progress":    progress,
		},
		"targets": targets,
	})
}

// DeleteProject deletes a project
func DeleteProject(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var project models.Project
	if err := database.DB.First(&project, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Project not found"})
		return
	}

	// Stop background tasks
	manager := workers.GetManager()
	manager.StopProjectTasks(project.ID)

	// Delete project (cascade deletes related records)
	if err := database.DB.Delete(&project).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  "deleted",
		"message": "Project and all related data deleted, background tasks stopped",
	})
}

// GetProjectFiles returns file tree structure
func GetProjectFiles(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var files []models.SourceFile
	database.DB.Where("project_id = ?", id).
		Select("id, relative_path, status, width, height").
		Find(&files)

	// Build tree structure
	tree := buildFileTree(files)

	c.JSON(http.StatusOK, tree)
}

// buildFileTree builds a tree structure from file list
func buildFileTree(files []models.SourceFile) map[string]interface{} {
	root := map[string]interface{}{
		"name":     "root",
		"key":      "root",
		"children": []interface{}{},
	}

	for _, f := range files {
		parts := strings.Split(f.RelativePath, string(filepath.Separator))
		current := root

		for i, part := range parts {
			isFile := i == len(parts)-1

			// Find existing node
			children := current["children"].([]interface{})
			var found map[string]interface{}
			for _, child := range children {
				childMap := child.(map[string]interface{})
				if childMap["name"] == part {
					found = childMap
					break
				}
			}

			if found != nil {
				current = found
			} else {
				newNode := map[string]interface{}{
					"name":     part,
					"children": []interface{}{},
					"isLeaf":   isFile,
				}

				if isFile {
					newNode["key"] = "file-" + strconv.Itoa(int(f.ID))
					newNode["file_id"] = f.ID
					newNode["status"] = f.Status
					newNode["dimensions"] = strconv.Itoa(f.Width) + "x" + strconv.Itoa(f.Height)
				} else {
					newNode["key"] = "dir-" + current["key"].(string) + "-" + part
				}

				children = append(children, newNode)
				current["children"] = children
				current = newNode
			}
		}
	}

	return root
}

// GetCandidates returns candidates for source files
func GetCandidates(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var req struct {
		FileIDs []uint `json:"file_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var project models.Project
	database.DB.First(&project, id)

	var sourceFiles []models.SourceFile
	database.DB.Preload("ComparisonCandidates").
		Preload("TargetSelections").
		Preload("SourceConfirmation").
		Where("id IN ?", req.FileIDs).
		Find(&sourceFiles)

	results := make(map[uint]interface{})

	for _, sf := range sourceFiles {
		// Group candidates by target
		candidatesByTarget := make(map[string][]map[string]interface{})

		for _, cand := range sf.ComparisonCandidates {
			var target models.ProjectTarget
			database.DB.First(&target, cand.ProjectTargetID)

			candidateData := map[string]interface{}{
				"id":         cand.ID,
				"path":       cand.FilePath,
				"similarity": cand.SimilarityScore,
				"width":      cand.Width,
				"height":     cand.Height,
			}

			candidatesByTarget[target.Name] = append(candidatesByTarget[target.Name], candidateData)
		}

		// Get target selections
		var targets []models.ProjectTarget
		database.DB.Where("project_id = ?", project.ID).Find(&targets)

		targetSelections := make(map[string]interface{})
		for _, target := range targets {
			var selection models.TargetSelection
			database.DB.Where("source_file_id = ? AND project_target_id = ?", sf.ID, target.ID).First(&selection)

			targetSelections[target.Name] = map[string]interface{}{
				"selected_candidate_id": selection.SelectedCandidateID,
				"no_match":              selection.NoMatch,
			}
		}

		confirmed := false
		if sf.SourceConfirmation != nil {
			confirmed = sf.SourceConfirmation.Confirmed
		}

		results[sf.ID] = map[string]interface{}{
			"source": map[string]interface{}{
				"path":       sf.FullPath,
				"relative":   sf.RelativePath,
				"thumb_url":  "/api/image?path=" + sf.FullPath,
				"width":      sf.Width,
				"height":     sf.Height,
				"size_bytes": sf.SizeBytes,
			},
			"candidates":        candidatesByTarget,
			"target_selections": targetSelections,
			"confirmed":         confirmed,
		}
	}

	c.JSON(http.StatusOK, results)
}

// ServeImage serves an image file
func ServeImage(c *gin.Context) {
	path := c.Query("path")
	c.File(path)
}

// SelectCandidate selects a candidate for a target
func SelectCandidate(c *gin.Context) {
	var req struct {
		SourceFileID        uint  `json:"source_file_id"`
		ProjectTargetID     uint  `json:"project_target_id"`
		SelectedCandidateID *uint `json:"selected_candidate_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var selection models.TargetSelection
	database.DB.Where("source_file_id = ? AND project_target_id = ?",
		req.SourceFileID, req.ProjectTargetID).FirstOrCreate(&selection)

	selection.SelectedCandidateID = req.SelectedCandidateID
	selection.NoMatch = false
	database.DB.Save(&selection)

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// MarkNoMatch marks a target as having no match
func MarkNoMatch(c *gin.Context) {
	var req struct {
		SourceFileID    uint `json:"source_file_id"`
		ProjectTargetID uint `json:"project_target_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var selection models.TargetSelection
	database.DB.Where("source_file_id = ? AND project_target_id = ?",
		req.SourceFileID, req.ProjectTargetID).FirstOrCreate(&selection)

	selection.SelectedCandidateID = nil
	selection.NoMatch = true
	database.DB.Save(&selection)

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// ConfirmRow confirms/unconfirms a source file
func ConfirmRow(c *gin.Context) {
	var req struct {
		SourceFileID uint `json:"source_file_id"`
		Confirmed    bool `json:"confirmed"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var confirmation models.SourceConfirmation
	database.DB.Where("source_file_id = ?", req.SourceFileID).FirstOrCreate(&confirmation)

	confirmation.Confirmed = req.Confirmed
	if req.Confirmed {
		now := time.Now()
		confirmation.ConfirmedAt = &now
	} else {
		confirmation.ConfirmedAt = nil
	}
	database.DB.Save(&confirmation)

	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// StartExport starts export process
func StartExport(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var req struct {
		UsePlaceholder bool   `json:"use_placeholder"`
		OnlyConfirmed  bool   `json:"only_confirmed"`
		OutputPath     string `json:"output_path"`
	}
	c.ShouldBindJSON(&req)

	var project models.Project
	if err := database.DB.First(&project, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Project not found"})
		return
	}

	manager := workers.GetManager()
	manager.StartExport(project.ID, func(ctx context.Context) {
		svc := services.NewExportService(&project, req.UsePlaceholder, req.OnlyConfirmed, req.OutputPath, ctx)
		if err := svc.Process(); err != nil {
			log.Printf("Export failed for project %d: %v", project.ID, err)
		}
	})

	c.JSON(http.StatusOK, gin.H{"status": "exporting"})
}

// GetExportProgress returns export progress
func GetExportProgress(c *gin.Context) {
	id, _ := strconv.Atoi(c.Param("id"))

	var project models.Project
	if err := database.DB.First(&project, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Project not found"})
		return
	}

	// For now, return empty progress
	// TODO: Implement progress file reading
	c.JSON(http.StatusOK, gin.H{
		"total":     0,
		"processed": 0,
		"current":   "",
	})
}
