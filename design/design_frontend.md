# Frontend Design

## Stack
- React 18
- Vite
- TypeScript
- Ant Design 5.x
- Jotai (State Management)
- Axios

## Directory Structure
```
src/
  api/          # Axios wrappers
  components/   # Shared components
  pages/
    ProjectList/
    ProjectDetail/
      QuickCompare/
  store/        # Jotai atoms
  types/        # TS interfaces
```

## Pages

### 1. Project List (`/projects`)
- **Layout**: Standard Table.
- **Columns**: Name, Source Path, Status (Tag), Proc Time (Live Timer), Actions (Enter, Delete).
- **Polling**: `useInterval` hook to fetch list every 30s.
- **Create Modal**: Form with Dynamic List for Target Directories.

### 2. Project Detail (`/projects/:id`)
- **Layout**: Sidebar (Left) + Main Content.
- **Sidebar**:
  - Project Info (Name, Status)
  - Nav: [Quick Compare]
- **Main**: Outlet.

### 3. Quick Compare (`/projects/:id/compare`)
- **Header**:
  - Filters: Name search, Size range (all client-side filtering if valid, or server-side).
    - Given "filtering around Source Directory", probably filter the Tree View.
  - Actions: Export Button.
- **Body** (Split View):
  - **Left (Tree)**: `DirectoryTree` component.
    - Data: Recursive structure from `GET /files`.
    - Checkbox: "Checked" means Confirmation.
    - Click node: Scroll/Highlight row in right table (or filter table to this folder).
    - *Requirement Check*: "Left is Tree... Right is Table rows are files".
    - Actually, maybe the Right Table *is* the list of files in the currently selected folder? Or the Right Table is a flat list of ALL files?
    - *User says*: "Left is fully mapped Source Directory... Right is Table... Rows are potential images".
    - Interaction: Likely clicking a folder in Left filters Right to show files in that folder. Or if "Root" is selected, show all (might be slow).
    - *Optimization*: Default to showing flat list of *all* files? No, tree usually filters.
    - Let's assume: Clicking Tree Node -> Show files in that node (children) in the Table.
  - **Right (Table)**:
    - Columns: 
      - Source File (Name + Thumb)
      - [Target Name A] (Candidate Image + Score)
      - [Target Name B] ...
      - Action (Confirm)
    - Row Selection: Highlighting.

## State Management (Jotai)
- `projectAtom`: Current project details.
- `filesAtom`: Full file tree.
- `filtersAtom`: Current active filters.
