# Look Alike - Project Walkthrough

## Overview
This is a local web application for managing and comparing image directories to find similarities. It consists of a Ruby (Sinatra) backend and a React (Vite) frontend.

## Architecture
- **Backend**: Ruby 3 + Sinatra + SQLite3 + RMagick (Image Processing).
- **Frontend**: React + TypeScript + Ant Design + Jotai.
- **Communication**: REST API (Frontend proxies `/api` to Backend :4567).

## Features Implemented
1. **Project Management**: Create projects with Source Directory and multiple Target Directories.
2. **Background Processing**:
   - Scans Source Directory.
   - Compares images against Targets using `pHash`, `dHash`, etc.
   - Updates status in real-time (via polling).
3. **Quick Compare Interface**:
   - **Left**: Directory Tree of Sources.
   - **Right**: Comparison Table showing best matches from Targets.
   - **Action**: Confirm matches.
4. **Export**:
   - Copies confirmed matches to an Output directory.
   - Preserves Source directory structure.
   - Renames files to match Source filenames (but keeps Target extension).

## Setup & Run

### Backend
The backend runs on port 4567.
```bash
cd server
bundle install
bundle exec rake db:migrate
bundle exec ruby app.rb
```

### Frontend
The frontend runs on port 5173.
```bash
cd client
npm install
npm run dev
```

## Usage
1. Open `http://localhost:5173`.
2. Click **New Project**.
3. Enter "Activity Name" and "Source Directory" (Absolute path).
4. Add one or more "Target Directories".
5. Click **Create**.
6. Wait for status to change from `Pending` -> `Processing` -> `Completed`.
7. Click **Enter** to view the **Quick Compare** page.
8. Browse the tree, verify matches in the table, and check "Confirm".
9. Click **Export Selected** to save files.

## Notes
- Ensure absolute paths are correct for your local machine.
- Large directories might take time to process (Logic is currently single-threaded naive loop for MVP).
