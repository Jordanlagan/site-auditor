module Tests
  module V1
    class DesignMobileResponsiveTest < BaseTest
      def run!
        return not_applicable unless page_data&.metadata.present?

        # Check viewport meta tag
        has_viewport = check_viewport_meta

        # Check if we have mobile screenshot
        has_mobile_screenshot = page_data.screenshots.dig("mobile").present?

        if has_viewport && has_mobile_screenshot
          # Use AI to analyze mobile screenshot quality
          analyze_mobile_design
        elsif has_viewport
          create_result(
            status: "warning",
            score: 70,
            summary: "Viewport meta tag is present, but mobile rendering could not be verified.",
            details: { has_viewport_meta: true },
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 0,
            summary: "No viewport meta tag found. Site is not configured for mobile responsiveness.",
            recommendation: 'Add a viewport meta tag to the <head>: <meta name="viewport" content="width=device-width, initial-scale=1">',
            priority: 5
          )
        end
      rescue => e
        Rails.logger.error "DesignMobileResponsiveTest failed: #{e.message}"
        not_applicable
      end

      protected

      def test_category
        "design"
      end

      def check_viewport_meta
        doc = Nokogiri::HTML(page_data.html_content)
        viewport = doc.at_css('meta[name="viewport"]')
        viewport.present?
      end

      def analyze_mobile_design
        prompt = <<~PROMPT
          Based on the available data, determine if the website appears to be properly responsive for mobile devices.

          Consider:
          - Presence of viewport meta tag
          - Content width and overflow
          - Element sizes and spacing
          - Text readability

          Make your best assessment of mobile responsiveness.
        PROMPT

        data_context = {
          viewport_meta: page_data.metadata["viewport"],
          has_mobile_screenshot: true,
          images_count: page_data.images.size,
          scripts_count: page_data.scripts.size
        }

        analyze_with_ai(prompt, data_context)
      end
    end
  end
end
