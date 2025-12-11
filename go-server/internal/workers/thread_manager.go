package workers

import (
	"context"
	"fmt"
	"sync"
)

// TaskType represents the type of background task
type TaskType string

const (
	TaskTypeComparison TaskType = "comparison"
	TaskTypeExport     TaskType = "export"
)

// Task represents a background task
type Task struct {
	ProjectID uint
	Type      TaskType
	Cancel    context.CancelFunc
}

// ThreadManager manages background tasks
type ThreadManager struct {
	tasks map[string]*Task // key: "projectID-type"
	mu    sync.RWMutex
}

var globalManager = &ThreadManager{
	tasks: make(map[string]*Task),
}

// GetManager returns the global thread manager instance
func GetManager() *ThreadManager {
	return globalManager
}

// StartComparison starts a comparison task for a project
func (tm *ThreadManager) StartComparison(projectID uint, fn func(ctx context.Context)) {
	tm.startTask(projectID, TaskTypeComparison, fn)
}

// StartExport starts an export task for a project
func (tm *ThreadManager) StartExport(projectID uint, fn func(ctx context.Context)) {
	tm.startTask(projectID, TaskTypeExport, fn)
}

// startTask starts a background task
func (tm *ThreadManager) startTask(projectID uint, taskType TaskType, fn func(ctx context.Context)) {
	key := tm.makeKey(projectID, taskType)

	tm.mu.Lock()
	// Stop existing task if any
	if existingTask, exists := tm.tasks[key]; exists {
		existingTask.Cancel()
		delete(tm.tasks, key)
	}

	// Create new context with cancel
	ctx, cancel := context.WithCancel(context.Background())

	// Store task
	tm.tasks[key] = &Task{
		ProjectID: projectID,
		Type:      taskType,
		Cancel:    cancel,
	}
	tm.mu.Unlock()

	// Run task in goroutine
	go func() {
		defer func() {
			// Clean up task when done
			tm.mu.Lock()
			delete(tm.tasks, key)
			tm.mu.Unlock()
		}()

		fn(ctx)
	}()

	fmt.Printf("Started %s task for project %d\n", taskType, projectID)
}

// StopProjectTasks stops all tasks for a specific project
func (tm *ThreadManager) StopProjectTasks(projectID uint) {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	for key, task := range tm.tasks {
		if task.ProjectID == projectID {
			task.Cancel()
			delete(tm.tasks, key)
			fmt.Printf("Stopped %s task for project %d\n", task.Type, projectID)
		}
	}
}

// StopTask stops a specific task
func (tm *ThreadManager) StopTask(projectID uint, taskType TaskType) {
	key := tm.makeKey(projectID, taskType)

	tm.mu.Lock()
	defer tm.mu.Unlock()

	if task, exists := tm.tasks[key]; exists {
		task.Cancel()
		delete(tm.tasks, key)
		fmt.Printf("Stopped %s task for project %d\n", taskType, projectID)
	}
}

// IsTaskRunning checks if a task is running
func (tm *ThreadManager) IsTaskRunning(projectID uint, taskType TaskType) bool {
	key := tm.makeKey(projectID, taskType)

	tm.mu.RLock()
	defer tm.mu.RUnlock()

	_, exists := tm.tasks[key]
	return exists
}

// makeKey creates a unique key for a task
func (tm *ThreadManager) makeKey(projectID uint, taskType TaskType) string {
	return fmt.Sprintf("%d-%s", projectID, taskType)
}
