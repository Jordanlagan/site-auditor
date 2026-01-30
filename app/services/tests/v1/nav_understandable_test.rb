module Tests
  module V1
    class NavUnderstandableTest < BaseTest
      def run!
        return not_applicable(summary: "No navigation data available") unless page_data&.html_content.present?

        nav_items = extract_nav_text

        analyze_with_ai(
          "Is the primary navigation understandable in 1 pass, with no jargon?",
          {
            nav_items: nav_items,
            analysis_points: [
              "Are menu labels clear and descriptive?",
              "Is industry jargon avoided?",
              "Would a first-time visitor understand these labels?",
              "Are labels actionable and user-focused?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "NavUnderstandableTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze navigation clarity")
      end

      protected

      def test_category
        "nav"
      end

      def extract_nav_text
        doc = Nokogiri::HTML(page_data.html_content)
        nav = doc.at_css("nav") || doc.at_css("header nav")
        return [] unless nav

        nav.css("a").map { |link| link.text.strip }.reject(&:empty?)
      end
    end
  end
end
