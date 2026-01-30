class Audit < ApplicationRecord
  has_many :audit_issues, dependent: :destroy
  has_many :discovered_pages, dependent: :destroy
  has_many :audit_questions, dependent: :destroy
  has_many :test_results, dependent: :destroy

  # Audit modes
  MODES = %w[single_page full_crawl].freeze

  # Status enum
  STATUSES = %w[pending crawling collecting testing complete failed].freeze

  # Phases for full_crawl mode
  PHASES = %w[crawling prioritizing collecting testing synthesizing].freeze

  # Test categories
  CATEGORIES = %w[nav structure cro design reviews price speed].freeze

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :audit_mode, inclusion: { in: MODES }
  validates :overall_score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

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

  # Calculate overall score from test results
  def calculate_overall_score!
    results = test_results.where.not(status: "not_applicable")
    return if results.empty?

    passed_count = results.where(status: "passed").count
    total_count = results.count

    self.overall_score = ((passed_count.to_f / total_count) * 100).round
    save
  end

  # Get category scores
  def category_scores
    scores = {}
    CATEGORIES.each do |category|
      category_results = test_results.where(test_category: category).where.not(status: "not_applicable")
      next if category_results.empty?

      passed = category_results.where(status: "passed").count
      total = category_results.count
      scores[category] = ((passed.to_f / total) * 100).round
    end
    scores
  end

  # Get failed tests count
  def failed_tests_count
    test_results.where(status: "failed").count
  end

  # Get warning tests count
  def warning_tests_count
    test_results.where(status: "warning").count
  end

  # Get passed tests count
  def passed_tests_count
    test_results.where(status: "passed").count
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
