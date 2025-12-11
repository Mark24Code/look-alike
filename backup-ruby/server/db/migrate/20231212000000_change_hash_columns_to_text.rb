class ChangeHashColumnsToText < ActiveRecord::Migration[7.2]
  def up
    # Change hash columns from bigint to text for both source_files and target_files
    change_column :source_files, :phash, :text
    change_column :source_files, :ahash, :text
    change_column :source_files, :dhash, :text

    change_column :target_files, :phash, :text
    change_column :target_files, :ahash, :text
    change_column :target_files, :dhash, :text
  end

  def down
    change_column :source_files, :phash, :bigint
    change_column :source_files, :ahash, :bigint
    change_column :source_files, :dhash, :bigint

    change_column :target_files, :phash, :bigint
    change_column :target_files, :ahash, :bigint
    change_column :target_files, :dhash, :bigint
  end
end
