class TestResult < ApplicationRecord
  belongs_to :discovered_page
  belongs_to :audit
  belongs_to :test, primary_key: :test_key, foreign_key: :test_key, optional: true

  STATUSES = %w[passed failed not_applicable].freeze

  validates :test_key, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :passed, -> { where(status: "passed") }
  scope :failed, -> { where(status: "failed") }
  scope :by_category, ->(category) { where(test_category: category) }

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  def not_applicable?
    status == "not_applicable"
  end

  def human_test_name
    test_key.humanize.titleize
  end
end
