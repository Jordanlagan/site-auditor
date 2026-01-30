class AuditIssue < ApplicationRecord
  belongs_to :audit

  # Severities
  SEVERITIES = %w[low medium high].freeze
  
  # Categories match Audit::CATEGORIES - ordered by business impact
  CATEGORIES = %w[cro_ux performance seo security accessibility].freeze

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :severity, presence: true, inclusion: { in: SEVERITIES }
  validates :title, presence: true
  validates :description, presence: true

  scope :by_category, ->(category) { where(category: category) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :high_severity, -> { where(severity: 'high') }
  scope :medium_severity, -> { where(severity: 'medium') }
  scope :low_severity, -> { where(severity: 'low') }
  scope :ordered_by_severity, -> { order(Arel.sql("CASE severity WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 END")) }

  # Severity helpers
  def high?
    severity == 'high'
  end

  def medium?
    severity == 'medium'
  end

  def low?
    severity == 'low'
  end
end
