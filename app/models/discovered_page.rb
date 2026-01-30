class DiscoveredPage < ApplicationRecord
  belongs_to :audit
  has_many :page_screenshots, dependent: :destroy
  has_many :audit_questions, dependent: :destroy
  has_many :adaptive_tests, dependent: :destroy
  has_one :page_data, dependent: :destroy
  has_many :test_results, dependent: :destroy

  validates :url, presence: true
  validates :data_collection_status, inclusion: { in: %w[pending collecting complete failed] }
  validates :testing_status, inclusion: { in: %w[pending testing complete failed] }

  scope :by_priority, -> { order(priority_score: :desc) }
  scope :high_priority, -> { where(is_priority_page: true) }
  scope :data_pending, -> { where(data_collection_status: "pending") }
  scope :data_complete, -> { where(data_collection_status: "complete") }
  scope :testing_pending, -> { where(testing_status: "pending") }
  scope :testing_complete, -> { where(testing_status: "complete") }

  PAGE_TYPES = %w[
    homepage
    product
    collection
    about
    contact
    blog_home
    article
    other
  ].freeze

  def needs_data_collection?
    data_collection_status == "pending"
  end

  def ready_for_testing?
    data_collection_status == "complete" && testing_status == "pending" && page_data.present?
  end

  def data_collection_complete?
    data_collection_status == "complete" && page_data&.has_complete_data?
  end

  def all_tests_complete?
    testing_status == "complete"
  end
end
