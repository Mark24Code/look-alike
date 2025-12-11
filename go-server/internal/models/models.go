package models

import (
	"time"
)

// Project represents a comparison project
type Project struct {
	ID           uint       `gorm:"primarykey" json:"id"`
	Name         string     `gorm:"not null" json:"name"`
	SourcePath   string     `gorm:"not null" json:"source_path"`
	Status       string     `gorm:"default:pending" json:"status"` // pending, processing, indexed, comparing, completed, error
	ErrorMessage *string    `json:"error_message,omitempty"`
	StartedAt    *time.Time `json:"started_at,omitempty"`
	EndedAt      *time.Time `json:"ended_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`

	// Associations
	ProjectTargets []ProjectTarget `gorm:"foreignKey:ProjectID;constraint:OnDelete:CASCADE" json:"targets,omitempty"`
	SourceFiles    []SourceFile    `gorm:"foreignKey:ProjectID;constraint:OnDelete:CASCADE" json:"source_files,omitempty"`
}

// TableName specifies the table name for Project
func (Project) TableName() string {
	return "projects"
}

// ProjectTarget represents a target directory for comparison
type ProjectTarget struct {
	ID        uint   `gorm:"primarykey" json:"id"`
	ProjectID uint   `gorm:"not null;index" json:"project_id"`
	Name      string `json:"name"`
	Path      string `json:"path"`

	// Associations
	Project              *Project              `gorm:"foreignKey:ProjectID;constraint:OnDelete:CASCADE" json:"-"`
	TargetFiles          []TargetFile          `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
	ComparisonCandidates []ComparisonCandidate `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
	TargetSelections     []TargetSelection     `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
}

// TableName specifies the table name for ProjectTarget
func (ProjectTarget) TableName() string {
	return "project_targets"
}

// SourceFile represents a source image file
type SourceFile struct {
	ID           uint      `gorm:"primarykey" json:"id"`
	ProjectID    uint      `gorm:"not null;index:idx_project_relative,priority:1;index" json:"project_id"`
	RelativePath string    `gorm:"index:idx_project_relative,priority:2" json:"relative_path"`
	FullPath     string    `json:"full_path"`
	Width        int       `json:"width"`
	Height       int       `json:"height"`
	SizeBytes    int64     `json:"size_bytes"`
	Status       string    `gorm:"default:pending" json:"status"` // pending, indexed, analyzed
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`

	// Computed fields
	AspectRatio float64 `gorm:"index" json:"aspect_ratio,omitempty"`
	Area        int     `gorm:"index" json:"area,omitempty"`

	// Hash values (stored as text)
	Phash     string `gorm:"type:text" json:"phash,omitempty"`
	Ahash     string `gorm:"type:text" json:"ahash,omitempty"`
	Dhash     string `gorm:"type:text" json:"dhash,omitempty"`
	Histogram string `gorm:"type:text" json:"histogram,omitempty"` // JSON array

	// Associations
	Project              *Project              `gorm:"foreignKey:ProjectID;constraint:OnDelete:CASCADE" json:"-"`
	SourceConfirmation   *SourceConfirmation   `gorm:"foreignKey:SourceFileID" json:"confirmation,omitempty"`
	TargetSelections     []TargetSelection     `gorm:"foreignKey:SourceFileID;constraint:OnDelete:CASCADE" json:"-"`
	ComparisonCandidates []ComparisonCandidate `gorm:"foreignKey:SourceFileID;constraint:OnDelete:CASCADE" json:"-"`
}

// TableName specifies the table name for SourceFile
func (SourceFile) TableName() string {
	return "source_files"
}

// TargetFile represents a target image file
type TargetFile struct {
	ID              uint      `gorm:"primarykey" json:"id"`
	ProjectTargetID uint      `gorm:"not null;index:idx_target_relative,priority:1;index" json:"project_target_id"`
	FullPath        string    `gorm:"not null" json:"full_path"`
	RelativePath    string    `gorm:"not null;index:idx_target_relative,priority:2" json:"relative_path"`
	Width           int       `json:"width"`
	Height          int       `json:"height"`
	SizeBytes       int64     `json:"size_bytes"`
	AspectRatio     float64   `gorm:"index" json:"aspect_ratio,omitempty"`
	Area            int       `gorm:"index" json:"area,omitempty"`
	Phash           string    `gorm:"type:text" json:"phash,omitempty"`
	Ahash           string    `gorm:"type:text" json:"ahash,omitempty"`
	Dhash           string    `gorm:"type:text" json:"dhash,omitempty"`
	Histogram       string    `gorm:"type:text" json:"histogram,omitempty"` // JSON array
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`

	// Associations
	ProjectTarget *ProjectTarget `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
}

// TableName specifies the table name for TargetFile
func (TargetFile) TableName() string {
	return "target_files"
}

// ComparisonCandidate represents a candidate match for a source file
type ComparisonCandidate struct {
	ID              uint    `gorm:"primarykey" json:"id"`
	SourceFileID    uint    `gorm:"not null;index" json:"source_file_id"`
	ProjectTargetID uint    `gorm:"not null;index" json:"project_target_id"`
	FilePath        string  `json:"file_path"`
	SimilarityScore float64 `json:"similarity_score"`
	Rank            int     `json:"rank"`
	Width           int     `json:"width"`
	Height          int     `json:"height"`

	// Associations
	SourceFile      *SourceFile      `gorm:"foreignKey:SourceFileID;constraint:OnDelete:CASCADE" json:"-"`
	ProjectTarget   *ProjectTarget   `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
	TargetSelection *TargetSelection `gorm:"foreignKey:SelectedCandidateID" json:"-"`
}

// TableName specifies the table name for ComparisonCandidate
func (ComparisonCandidate) TableName() string {
	return "comparison_candidates"
}

// TargetSelection represents the user's selection for a target
type TargetSelection struct {
	ID                  uint      `gorm:"primarykey" json:"id"`
	SourceFileID        uint      `gorm:"not null;uniqueIndex:idx_source_target;index" json:"source_file_id"`
	ProjectTargetID     uint      `gorm:"not null;uniqueIndex:idx_source_target;index" json:"project_target_id"`
	SelectedCandidateID *uint     `gorm:"index" json:"selected_candidate_id,omitempty"`
	NoMatch             bool      `gorm:"default:false" json:"no_match"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`

	// Associations
	SourceFile          *SourceFile          `gorm:"foreignKey:SourceFileID;constraint:OnDelete:CASCADE" json:"-"`
	ProjectTarget       *ProjectTarget       `gorm:"foreignKey:ProjectTargetID;constraint:OnDelete:CASCADE" json:"-"`
	ComparisonCandidate *ComparisonCandidate `gorm:"foreignKey:SelectedCandidateID;constraint:OnDelete:SET NULL" json:"candidate,omitempty"`
}

// TableName specifies the table name for TargetSelection
func (TargetSelection) TableName() string {
	return "target_selections"
}

// SourceConfirmation represents confirmation status for a source file
type SourceConfirmation struct {
	ID           uint       `gorm:"primarykey" json:"id"`
	SourceFileID uint       `gorm:"not null;uniqueIndex" json:"source_file_id"`
	Confirmed    bool       `gorm:"default:false" json:"confirmed"`
	ConfirmedAt  *time.Time `json:"confirmed_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`

	// Associations
	SourceFile *SourceFile `gorm:"foreignKey:SourceFileID;constraint:OnDelete:CASCADE" json:"-"`
}

// TableName specifies the table name for SourceConfirmation
func (SourceConfirmation) TableName() string {
	return "source_confirmations"
}
