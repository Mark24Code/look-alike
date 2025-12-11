package workers

import (
	"fmt"
	"sync"
)

// Job represents a unit of work
type Job func()

// WorkerPool manages a pool of goroutines to execute jobs
type WorkerPool struct {
	workerCount int
	jobs        chan Job
	wg          sync.WaitGroup
	started     bool
	mu          sync.Mutex
}

// NewWorkerPool creates a new worker pool with the specified number of workers
func NewWorkerPool(workerCount int) *WorkerPool {
	if workerCount <= 0 {
		workerCount = 4 // Default
	}

	return &WorkerPool{
		workerCount: workerCount,
		jobs:        make(chan Job, workerCount*2), // Buffer size
		started:     false,
	}
}

// Start starts the worker pool
func (wp *WorkerPool) Start() {
	wp.mu.Lock()
	defer wp.mu.Unlock()

	if wp.started {
		return
	}

	wp.started = true

	for i := 0; i < wp.workerCount; i++ {
		wp.wg.Add(1)
		go wp.worker(i)
	}

	fmt.Printf("Worker pool started with %d workers\n", wp.workerCount)
}

// worker is the goroutine that executes jobs
func (wp *WorkerPool) worker(id int) {
	defer wp.wg.Done()

	for job := range wp.jobs {
		job()
	}
}

// AddJob adds a job to the worker pool
func (wp *WorkerPool) AddJob(job Job) {
	wp.jobs <- job
}

// Stop stops the worker pool and waits for all jobs to complete
func (wp *WorkerPool) Stop() {
	wp.mu.Lock()
	if !wp.started {
		wp.mu.Unlock()
		return
	}
	wp.mu.Unlock()

	close(wp.jobs)
	wp.wg.Wait()
	fmt.Println("Worker pool stopped")
}
