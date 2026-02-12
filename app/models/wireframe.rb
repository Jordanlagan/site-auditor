class Wireframe < ApplicationRecord
  belongs_to :audit

  validates :title, presence: true
  validates :file_path, presence: true
  validates :config_used, presence: true

  # Delete HTML file when wireframe record is destroyed
  before_destroy :delete_html_file

  scope :recent, -> { order(created_at: :desc) }

  def html_content
    return nil unless file_path && File.exist?(full_file_path)
    File.read(full_file_path)
  end

  def full_file_path
    Rails.root.join("public", file_path.sub(%r{^/}, ""))
  end

  def url
    file_path
  end

  private

  def delete_html_file
    if file_path && File.exist?(full_file_path)
      File.delete(full_file_path)
      Rails.logger.info "Deleted wireframe file: #{full_file_path}"
    end
  rescue => e
    Rails.logger.error "Failed to delete wireframe file #{full_file_path}: #{e.message}"
  end
end
