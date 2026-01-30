module Tests
  module V1
    class NavStickyAccessibleTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Is the navigation menu sticky or easily accessible as the user scrolls?",
          {
            nav_html: primary_nav_html,
            nav_links: primary_nav_links,
            scripts: page_data.scripts&.map { |s| s["src"] }&.compact&.first(10),
            stylesheets: page_data.stylesheets&.map { |s| s["href"] }&.compact&.first(5),
            analysis_note: "Check for position:fixed, position:sticky in nav/header, or JavaScript scroll listeners"
          }
        )
      rescue => e
        Rails.logger.error "NavStickyAccessibleTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze navigation accessibility")
      end

      protected

      def test_category
        "nav"
      end
    end
  end
end
