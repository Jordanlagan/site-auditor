class Audit < ApplicationRecord
  has_many :audit_issues, dependent: :destroy
  has_many :discovered_pages, dependent: :destroy
  has_many :audit_questions, dependent: :destroy
  has_many :test_results, dependent: :destroy

  # Serialize test_ids as array
  attribute :test_ids, :integer, array: true, default: []

  # Audit modes
  MODES = %w[single_page full_crawl].freeze

  # Status enum
  STATUSES = %w[pending crawling collecting testing complete failed].freeze

  # Phases for full_crawl mode
  PHASES = %w[crawling prioritizing collecting testing synthesizing].freeze

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :audit_mode, inclusion: { in: MODES }

  before_validation :normalize_url, if: :url_changed?
  before_validation :set_default_mode, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :crawling, -> { where(status: "crawling") }
  scope :collecting, -> { where(status: "collecting") }
  scope :testing, -> { where(status: "testing") }
  scope :complete, -> { where(status: "complete") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }
  scope :single_page_mode, -> { where(audit_mode: "single_page") }
  scope :full_crawl_mode, -> { where(audit_mode: "full_crawl") }

  # Mode helpers
  def single_page_mode?
    audit_mode == "single_page"
  end

  def full_crawl_mode?
    audit_mode == "full_crawl"
  end

  # Status helpers
  def pending?
    status == "pending"
  end

  def crawling?
    status == "crawling"
  end

  def collecting?
    status == "collecting"
  end

  def testing?
    status == "testing"
  end

  def complete?
    status == "complete"
  end

  def failed?
    status == "failed"
  end

  # Test count helpers
  def total_tests_count
    test_results.count
  end

  def passed_tests_count
    test_results.passed.count
  end

  def failed_tests_count
    test_results.failed.count
  end

  def pass_rate
    return 0 if total_tests_count.zero?
    (passed_tests_count.to_f / total_tests_count * 100).round
  end

  # Get warning tests count (keeping for compatibility)
  def warning_tests_count
    0 # We don't have warnings anymore
  end

  private

  def set_default_mode
    self.audit_mode ||= "single_page"
  end

  def normalize_url
    return unless url.present?

    # Add http:// if no scheme provided
    self.url = "http://#{url}" unless url.match?(/\Ahttps?:\/\//)

    # Parse and normalize
    uri = URI.parse(url)
    uri.path = "/" if uri.path.blank?
    self.url = uri.to_s
  rescue URI::InvalidURIError
    # Let validation handle invalid URLs
  end
end
