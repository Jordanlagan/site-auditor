class PageScreenshot < ApplicationRecord
  belongs_to :discovered_page

  validates :device_type, inclusion: { in: %w[desktop mobile] }
  validates :screenshot_url, presence: true

  scope :desktop, -> { where(device_type: "desktop") }
  scope :mobile, -> { where(device_type: "mobile") }
end
