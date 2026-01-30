class PageData < ApplicationRecord
  belongs_to :discovered_page

  validates :discovered_page_id, presence: true, uniqueness: true

  # Serialize JSONB fields with defaults
  attribute :fonts, :jsonb, default: []
  attribute :colors, :jsonb, default: []
  attribute :images, :jsonb, default: []
  attribute :scripts, :jsonb, default: []
  attribute :stylesheets, :jsonb, default: []
  attribute :asset_distribution, :jsonb, default: {}
  attribute :performance_metrics, :jsonb, default: {}
  attribute :headings, :jsonb, default: { h1: [], h2: [], h3: [], h4: [], h5: [], h6: [] }
  attribute :links, :jsonb, default: []
  attribute :meta_tags, :jsonb, default: {}
  attribute :structured_data, :jsonb, default: []
  attribute :screenshots, :jsonb, default: {}
  attribute :metadata, :jsonb, default: {}

  # Helper methods
  def has_complete_data?
    html_content.present? &&
    screenshots.present? &&
    performance_metrics.present?
  end

  def total_assets_count
    images.size + scripts.size + stylesheets.size + fonts.size
  end

  def page_weight_mb
    return 0 unless total_page_weight_bytes
    (total_page_weight_bytes / 1_048_576.0).round(2)
  end

  def all_content
    [
      page_content,
      headings.values.flatten,
      links.map { |l| l["text"] },
      meta_title,
      meta_description
    ].flatten.compact.join(" ")
  end
end
