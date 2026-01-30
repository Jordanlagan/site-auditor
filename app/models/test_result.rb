class TestResult < ApplicationRecord
  belongs_to :discovered_page
  belongs_to :audit

  STATUSES = %w[passed failed warning not_applicable].freeze
  CATEGORIES = %w[nav structure cro design reviews price speed].freeze

  validates :test_key, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :test_category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

  attribute :details, :jsonb, default: {}

  scope :passed, -> { where(status: "passed") }
  scope :failed, -> { where(status: "failed") }
  scope :warning, -> { where(status: "warning") }
  scope :by_category, ->(category) { where(test_category: category) }
  scope :high_priority, -> { where("priority >= ?", 4) }

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  def warning?
    status == "warning"
  end

  def not_applicable?
    status == "not_applicable"
  end

  def human_test_name
    test_key.humanize.titleize
  end
end
