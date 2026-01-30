module Tests
  module V1
    class NavCurrentPageFeedbackTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Is there visual feedback showing which page the user is currently on?",
          {
            nav_html: extract_nav_html,
            current_url: discovered_page.url,
            analysis_points: [
              "Are active nav items highlighted?",
              "Is there an 'active' or 'current' class?",
              "Do active items have different styling?",
              "Can users tell where they are in the site?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "NavCurrentPageFeedbackTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze navigation feedback")
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
