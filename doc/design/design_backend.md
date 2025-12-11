# Backend Design (Sinatra)

## Architecture
- **Language**: Ruby 3.x
- **Framework**: Sinatra (Modular style)
- **JSON handling**: `json` gem
- **CORS**: `rack-cors` to allow frontend calls
- **Background Jobs**: Ruby `Thread` or simple loop checking a queue database table, sufficient for local single-user usage.

## API Endpoints

### Projects

- `GET /api/projects`
  - Query Params: `page`, `per_page`, `q` (search name)
  - Response: `{ projects: [...], total: n }`

- `POST /api/projects`
  - Body: `{ name: "...", source_path: "...", targets: [{name: "key", path: "..."}] }`
  - Logic:
    - Validate paths exist.
    - Create `Project` record.
    - Create `ProjectTarget` records.
    - Spawn Background Job to start processing:
      - Scan source dir.
      - Create `SourceFile` records.
      - For each source file, run comparison against Targets.
      - Update `Project` status to `processing` -> `completed`.
  - Response: `{ id: 1, ... }`

- `GET /api/projects/:id`
  - Response: Project details + Progress (source_files processed / total).

- `DELETE /api/projects/:id`
  - Logic: Delete DB records. Clean up any temp files (if any).

### Comparison View

- `GET /api/projects/:id/files`
  - Query Params: `files_only=true` (optional)
  - Purpose: Fetch the File Tree structure.
  - Response: Nested JSON representing the directory tree of Source Directory. Nodes include `id` of `source_files`.

- `GET /api/projects/:id/candidates`
  - Query Params: `source_file_ids=[...]` (Batch fetch)
  - Purpose: Get matches for the right-side table.
  - Response: `{ [source_file_id]: { [target_key_name]: { file_path: "...", similarity: 99.0 } } }`

- `POST /api/projects/:id/confirm`
  - Body: `{ source_file_id: 123, confirmed: true }`
  - Logic: Update/Create `Selection` record.

### Export

- `POST /api/projects/:id/export`
  - Logic:
    - Trigger background export script.
    - Iterate all confirmed selections.
    - Copy target file to `Output/{TargetName}/{RelativePath}`.
  - Response: `{ status: "exporting" }`

## Background Worker Pattern
- A simple `lib/worker.rb` that runs in a separate thread inside the Sinatra process or a separate process.
- Monitor `projects` with status `pending`.
- Status updates written to DB.
