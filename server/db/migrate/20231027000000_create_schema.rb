class CreateSchema < ActiveRecord::Migration[7.0]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :source_path
      t.string :status, default: 'pending'
      t.text :error_message
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end

    create_table :project_targets do |t|
      t.references :project, foreign_key: true
      t.string :name
      t.string :path
    end

    create_table :source_files do |t|
      t.references :project, foreign_key: true
      t.string :relative_path
      t.string :full_path
      t.integer :width
      t.integer :height
      t.integer :size_bytes
      t.string :status, default: 'pending'
      t.timestamps
    end
    add_index :source_files, [:project_id, :relative_path]

    create_table :comparison_candidates do |t|
      t.references :source_file, foreign_key: true
      t.references :project_target, foreign_key: true
      t.string :file_path
      t.float :similarity_score
      t.integer :rank
    end

    create_table :selections do |t|
      t.references :source_file, foreign_key: true
      t.boolean :confirmed, default: false
      t.text :selected_target_candidates # JSON array of IDs if needed
      t.timestamps
    end
  end
end
