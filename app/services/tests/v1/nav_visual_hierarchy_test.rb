module Tests
  module V1
    class NavVisualHierarchyTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        fonts = page_data.fonts || []
        colors = page_data.colors || []

        analyze_with_ai(
          "Is there a clear visual hierarchy in the navigation menu?",
          {
            nav_html: extract_nav_html,
            fonts_used: fonts.take(10),
            colors_used: colors.take(10),
            analysis_points: [
              "Are primary CTAs visually distinct?",
              "Is text size/weight used to show importance?",
              "Do colors create clear hierarchy?",
              "Is spacing used effectively?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "NavVisualHierarchyTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze navigation hierarchy")
      end

      protected

      def test_category
        "nav"
      end

      def extract_nav_html
        doc = Nokogiri::HTML(page_data.html_content)
        nav = doc.at_css("nav") || doc.at_css("header nav")
        nav ? nav.to_html.first(2000) : ""
      end
    end
  end
end
