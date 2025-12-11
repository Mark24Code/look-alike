class AddDimensionsToCandidates < ActiveRecord::Migration[7.0]
  def change
    add_column :comparison_candidates, :width, :integer
    add_column :comparison_candidates, :height, :integer
    
    # We want to select a specific candidate to be the "chosen one" for export/view
    add_column :selections, :selected_candidate_id, :integer
    add_index :selections, :selected_candidate_id
  end
end
