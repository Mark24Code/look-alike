package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/rs/cors"
)

// SetupRouter sets up the Gin router with all routes
func SetupRouter(clientDistPath string) *gin.Engine {
	router := gin.Default()

	// Setup CORS
	corsHandler := cors.New(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"*"},
		AllowCredentials: true,
	})

	router.Use(func(c *gin.Context) {
		corsHandler.HandlerFunc(c.Writer, c.Request)
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	// API routes
	api := router.Group("/api")
	{
		// Health check
		api.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status":  "ok",
				"version": "0.1.0",
			})
		})

		// Projects
		api.GET("/projects", GetProjects)
		api.POST("/projects", CreateProject)
		api.GET("/projects/:id", GetProject)
		api.DELETE("/projects/:id", DeleteProject)

		// Files
		api.GET("/projects/:id/files", GetProjectFiles)
		api.POST("/projects/:id/candidates", GetCandidates)

		// Image serving
		api.GET("/image", ServeImage)

		// Selections
		api.POST("/projects/:id/select_candidate", SelectCandidate)
		api.POST("/projects/:id/mark_no_match", MarkNoMatch)
		api.POST("/projects/:id/confirm_row", ConfirmRow)

		// Export
		api.POST("/projects/:id/export", StartExport)
		api.GET("/projects/:id/export_progress", GetExportProgress)
	}

	// Serve static files (frontend)
	if clientDistPath != "" {
		router.Static("/assets", clientDistPath+"/assets")
		router.StaticFile("/vite.svg", clientDistPath+"/vite.svg")

		// Serve index.html for all other routes (SPA fallback)
		router.NoRoute(func(c *gin.Context) {
			c.File(clientDistPath + "/index.html")
		})
	} else {
		router.NoRoute(func(c *gin.Context) {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "Frontend assets not found. Please run 'cd client && npm run build' first.",
			})
		})
	}

	return router
}
