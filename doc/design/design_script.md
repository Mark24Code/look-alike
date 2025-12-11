# Script & Algorithm Design

## 1. Image Comparison Logic (`lib/comparison_service.rb`)

We will adapt `@img-lib/compare_images.rb` into a reusable service class.

### Class: `BatchComparator`
- **Input**: Source Directory, hash of Target Directories `{'key' => 'path'}`.
- **Process**:
    1. **Indexing Targets**:
       - Iterate all Target Directories.
       - Pre-calculate hashes (pHash/dHash) for all images in targets? 
       - *optimization*: If target sets are large, caching these hashes in a local DB (or memory) is critical. For this MVP, we might compute on the fly if N is small, or pre-compute into a `target_file_indexes` table.
       - *Decision*: Since user mentioned "Server", we should index Target files into the DB (or memory struct) first to avoid re-reading for every source file.

    2. **Matching**:
       - For each file in Source Directory:
         - Calculate hash.
         - Compare against all indexed Target files.
         - Find top match (lowest distance / highest similarity).
         - Save to `comparison_candidates`.

### Algorithm Re-use
- Use existing `ImageComparator` class.
- Add `batch_compare(source_image, target_images_list)` method.

## 2. Export Script (`lib/exporter.rb`)

### Requirements
- Idempotent.
- Replicate directory structure.
- Rename to match source relative path.

### Logic
```ruby
def export(project_id)
  project = Project.find(project_id)
  selections = Selection.where(project_id: project_id, confirmed: true)
  
  selections.each do |sel|
    source_file = sel.source_file
    candidates = sel.candidates
    
    candidates.each do |cand|
        target_name = cand.target_key # e.g. "Draft1"
        
        # Source: /src/A/B/img.jpg -> Relative: A/B/img.jpg
        # Target Match: /scan/123.png
        
        # Dest: /Output/{start_time}/{target_name}/A/B/img.png
        # Note: Keep target extension or source? 
        # Requirement: "Reference relative position... rename"
        # Usually we keep the extension of the ACTUAL file (target), but name it after source.
        
        dest_dir = File.join(project.output_path, target_name, File.dirname(source_file.relative_path))
        FileUtils.mkdir_p(dest_dir)
        
        extension = File.extname(cand.file_path)
        dest_filename = File.basename(source_file.relative_path, ".*") + extension
        
        dest_path = File.join(dest_dir, dest_filename)
        
        FileUtils.cp(cand.file_path, dest_path) unless File.exist?(dest_path) && FileUtils.identical?(cand.file_path, dest_path)
    end
  end
end
```
