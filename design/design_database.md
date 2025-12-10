# Database Design

## Overview
We will use SQLite for its simplicity and file-based nature, fitting the "local server" requirement.

## Tables

### 1. projects
Stores the main project information.
- `id`: Integer, Primary Key, Auto Increment
- `name`: String, Project Name (Activity Name)
- `source_path`: String, Absolute path to source directory
- `status`: String, Enum('pending', 'processing', 'completed', 'error')
- `error_message`: Text, Optional
- `created_at`: Datetime
- `started_at`: Datetime
- `ended_at`: Datetime

### 2. project_targets
Stores the target directories configured for comparison.
- `id`: Integer, Primary Key
- `project_id`: Integer, Foreign Key -> projects.id
- `name`: String, The key/label for this target source
- `path`: String, Absolute path to target directory

### 3. source_files
Index of files found in the source directory.
- `id`: Integer, Primary Key
- `project_id`: Integer, Foreign Key -> projects.id
- `relative_path`: String, Path relative to source_path (e.g., "subdir/image.jpg")
- `full_path`: String, Cached absolute path
- `width`: Integer
- `height`: Integer
- `size_bytes`: Integer
- `status`: String, ('pending', 'analyzed')

### 4. comparison_candidates
Stores the found similar images from target directories for each source file.
- `id`: Integer, Primary Key
- `source_file_id`: Integer, Foreign Key -> source_files.id
- `project_target_id`: Integer, Foreign Key -> project_targets.id
- `file_path`: String, Absolute path of the found candidate
- `similarity_score`: Float (0-100)
- `rank`: Integer (1 being best match)
- `is_selected`: Boolean, Default false (or true if it's the only logic) but user confirms it separately?
    - *Clarification*: User validates the row.

### 5. selections
Stores the user's confirmation choices.
- `id`: Integer, Primary Key
- `source_file_id`: Integer, Unique Index (One selection per source file)
- `confirmed`: Boolean, True if user has confirmed this row.
- `selected_target_candidates`: Text (JSON), Store IDs of selected candidates if we allow choosing specific ones.
    - *Simplification*: The UI description implies "Right side is table... confirm at end of row". It suggests confirming the set of matches or the specific match.
    - Let's assume for now we confirm the *row* (Source File) and the matched candidates in the columns.

## Indexes
- `projects(created_at)`
- `source_files(project_id, relative_path)`
- `comparison_candidates(source_file_id)`
