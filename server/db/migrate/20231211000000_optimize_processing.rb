class OptimizeProcessing < ActiveRecord::Migration[7.0]
  def change
    # 新增target_files表
    create_table :target_files do |t|
      t.references :project_target, foreign_key: true
      t.string :full_path, null: false
      t.string :relative_path, null: false
      t.integer :width
      t.integer :height
      t.integer :size_bytes
      t.float :aspect_ratio  # 宽高比
      t.integer :area        # 面积

      # 预计算的哈希值
      t.bigint :phash
      t.bigint :ahash
      t.bigint :dhash
      t.text :histogram  # JSON array

      t.timestamps
    end

    add_index :target_files, [:project_target_id, :relative_path]
    add_index :target_files, :aspect_ratio
    add_index :target_files, :area

    # 为source_files添加索引字段
    add_column :source_files, :aspect_ratio, :float
    add_column :source_files, :area, :integer
    add_column :source_files, :phash, :bigint
    add_column :source_files, :ahash, :bigint
    add_column :source_files, :dhash, :bigint
    add_column :source_files, :histogram, :text

    add_index :source_files, :aspect_ratio
    add_index :source_files, :area

    # Selection表添加no_match字段
    add_column :selections, :no_match, :boolean, default: false
  end
end
