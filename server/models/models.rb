class Project < ActiveRecord::Base
  has_many :project_targets, dependent: :destroy
  has_many :source_files, dependent: :destroy
  
  validates :name, presence: true
  validates :source_path, presence: true
  
  def output_path
    # Define a convention for output, e.g., in user's home or adjacent to source
    # For now, let's say it's a 'exports' folder inside the project root for simplicity, 
    # or passed in environment.
    # User requirement: "Local server". 
    File.join(File.dirname(source_path), "#{name}_Output")
  end
end

class ProjectTarget < ActiveRecord::Base
  belongs_to :project
  has_many :comparison_candidates, dependent: :destroy
  has_many :target_files, dependent: :destroy
  has_many :target_selections, dependent: :destroy
end

class SourceFile < ActiveRecord::Base
  belongs_to :project
  has_one :source_confirmation, dependent: :destroy
  has_many :target_selections, dependent: :destroy
  has_many :comparison_candidates, dependent: :destroy
end

class ComparisonCandidate < ActiveRecord::Base
  belongs_to :source_file
  belongs_to :project_target
  has_many :target_selections, foreign_key: :selected_candidate_id, dependent: :nullify
end

class TargetSelection < ActiveRecord::Base
  belongs_to :source_file
  belongs_to :project_target
  belongs_to :comparison_candidate, foreign_key: :selected_candidate_id, optional: true

  validates :source_file_id, uniqueness: { scope: :project_target_id }
  validate :validate_no_match_exclusivity

  def validate_no_match_exclusivity
    if no_match && selected_candidate_id.present?
      errors.add(:no_match, "cannot be true when candidate is selected")
    end
  end
end

class SourceConfirmation < ActiveRecord::Base
  belongs_to :source_file

  validates :source_file_id, uniqueness: true
end

class TargetFile < ActiveRecord::Base
  belongs_to :project_target

  # 计算宽高比和面积
  before_save :calculate_dimensions

  def calculate_dimensions
    if width && height && height > 0
      self.aspect_ratio = width.to_f / height
      self.area = width * height
    end
  end

  # 从JSON解析直方图
  def histogram_array
    histogram ? JSON.parse(histogram) : []
  end

  def histogram_array=(arr)
    self.histogram = arr.to_json
  end
end
