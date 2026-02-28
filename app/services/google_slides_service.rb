class GoogleSlidesService
  # Returns: { slides_created: number, content: formatted_text }
  def export_audit_issues(audit:, prompt:)
    Rails.logger.info "Starting slides outline generation for audit #{audit.id}"

    slide_content = generate_slide_content(prompt)
    raise "Failed to generate slide content from AI" unless slide_content.present?

    slide_count = count_slides_in_content(slide_content)
    Rails.logger.info "Generated content with #{slide_count} slides"

    { slides_created: slide_count, content: slide_content }
  end

  private

  def generate_slide_content(prompt)
    Rails.logger.info "Calling Claude to generate slide content..."
    
    result = OpenaiService.chat(
      messages: [
        { role: "system", content: "You are an expert presentation designer and CRO analyst. Generate structured slide content based on website audit results." },
        { role: "user", content: prompt }
      ],
      model: "claude-opus-4-6",
      temperature: 0.3,
      max_tokens: 3000
    )

    Rails.logger.info "Claude generated structured slide content (#{result&.length || 0} chars)"
    result
  rescue => e
    Rails.logger.error "Failed to generate slide content: #{e.message}"
    raise "AI content generation failed: #{e.message}"
  end

  def count_slides_in_content(content)
    return 0 unless content.present?
    slide_count = content.scan(/\*\*Slide Title:/).length
    Rails.logger.info "Found #{slide_count} slides in generated content"
    slide_count
  end
end