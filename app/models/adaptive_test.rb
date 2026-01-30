class AdaptiveTest < ApplicationRecord
  belongs_to :discovered_page

  validates :test_type, presence: true

  scope :by_impact, -> { order(impact_score: :desc) }
  scope :high_impact, -> { where("impact_score >= ?", 70) }

  TEST_TYPES = %w[
    contrast_analysis
    cta_prominence
    typography_scan
    color_palette
    layout_density
    trust_signals
    form_friction
    mobile_usability
  ].freeze
end
