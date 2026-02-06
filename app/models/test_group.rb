class TestGroup < ApplicationRecord
  has_many :tests, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a valid hex color" }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def tests_count
    tests.active.count
  end
end
