class Test < ApplicationRecord
  belongs_to :test_group
  has_many :test_results, primary_key: :test_key, foreign_key: :test_key, dependent: :destroy

  # Available data sources that match what we actually collect
  DATA_SOURCES = %w[
    html_content
    page_content
    fonts
    colors
    images
    scripts
    stylesheets
    headings
    links
    meta_title
    meta_description
    meta_tags
    structured_data
    performance_metrics
    asset_distribution
    total_page_weight
  ].freeze

  validates :name, presence: true
  validates :test_key, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9_]+\z/, message: "must be lowercase letters, numbers, and underscores only" }
  validates :test_details, presence: true
  validates :data_sources, presence: true

  validate :data_sources_are_valid

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }
  scope :by_group, ->(group_id) { where(test_group_id: group_id) }

  # Serialize arrays as JSONB
  attribute :data_sources, :jsonb, default: []

  def export_json
    {
      name: name,
      description: description,
      test_key: test_key,
      test_details: test_details,
      data_sources: data_sources,
      test_group: test_group.name
    }
  end

  def self.import_from_json(json_data, test_group)
    create!(
      test_group: test_group,
      name: json_data["name"],
      description: json_data["description"],
      test_key: json_data["test_key"],
      test_details: json_data["test_details"],
      data_sources: json_data["data_sources"] || []
    )
  end

  private

  def data_sources_are_valid
    return if data_sources.blank?

    invalid_sources = data_sources - DATA_SOURCES
    if invalid_sources.any?
      errors.add(:data_sources, "contains invalid sources: #{invalid_sources.join(', ')}")
    end
  end
end
