class AuditQuestion < ApplicationRecord
  belongs_to :audit
  belongs_to :discovered_page, optional: true

  validates :question_type, presence: true
  validates :question_text, presence: true
  validates :status, inclusion: { in: %w[pending answered skipped] }

  scope :pending, -> { where(status: "pending") }
  scope :answered, -> { where(status: "answered") }
  scope :for_page, ->(page_id) { where(discovered_page_id: page_id) }

  QUESTION_TYPES = {
    cta_identification: "Which element is the primary call-to-action?",
    page_purpose: "What is the primary purpose of this page?",
    competing_actions: "Are there competing actions on this page?",
    target_audience: "Who is the target audience?",
    conversion_goal: "What action should visitors take?",
    clarity_check: "Is the value proposition clear?"
  }.freeze

  def mark_answered!(response)
    update!(
      user_response: response,
      status: "answered"
    )
  end
end
