class RefactorSelectionToMultiTarget < ActiveRecord::Migration[7.2]
  def up
    # 创建新的 target_selections 表 - 存储每个源文件在每个目标列的选择
    create_table :target_selections do |t|
      t.integer :source_file_id, null: false
      t.integer :project_target_id, null: false
      t.integer :selected_candidate_id
      t.boolean :no_match, default: false
      t.timestamps
    end

    # 添加索引
    add_index :target_selections, [:source_file_id, :project_target_id], unique: true, name: 'index_target_selections_on_source_and_target'
    add_index :target_selections, :selected_candidate_id

    # 添加外键约束
    add_foreign_key :target_selections, :source_files
    add_foreign_key :target_selections, :project_targets
    add_foreign_key :target_selections, :comparison_candidates, column: :selected_candidate_id

    # 创建新的 source_confirmations 表 - 存储整行的确认状态
    create_table :source_confirmations do |t|
      t.integer :source_file_id, null: false
      t.boolean :confirmed, default: false
      t.datetime :confirmed_at
      t.timestamps
    end

    # 添加索引
    add_index :source_confirmations, :source_file_id, unique: true

    # 添加外键约束
    add_foreign_key :source_confirmations, :source_files

    # 删除旧的 selections 表
    drop_table :selections if table_exists?(:selections)
  end

  def down
    # 回滚：重新创建 selections 表
    create_table :selections do |t|
      t.integer :source_file_id
      t.boolean :confirmed, default: false
      t.text :selected_target_candidates
      t.integer :selected_candidate_id
      t.boolean :no_match, default: false
      t.timestamps
    end

    add_index :selections, :source_file_id
    add_index :selections, :selected_candidate_id
    add_foreign_key :selections, :source_files

    # 删除新表
    drop_table :target_selections if table_exists?(:target_selections)
    drop_table :source_confirmations if table_exists?(:source_confirmations)
  end
end
