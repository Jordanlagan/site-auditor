class Test < ApplicationRecord
  belongs_to :test_group
  has_many :test_results, primary_key: :test_key, foreign_key: :test_key, dependent: :destroy

  # Available data sources - consolidated and organized
  DATA_SOURCES = %w[
    page_content
    page_html
    headings
    asset_urls
    performance_data
    internal_links
    external_links
    colors
    screenshots
    html_content
    fonts
    images
    scripts
    stylesheets
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
end
