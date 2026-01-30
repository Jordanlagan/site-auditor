module Tests
  module V1
    class NavItemCountTest < BaseTest
      def run!
        return not_applicable unless has_nav_data?

        nav_items = count_top_level_nav_items

        if nav_items <= 7
          create_result(
            status: "passed",
            score: 100,
            summary: "Navigation has #{nav_items} top-level items, which is within the recommended limit of 7.",
            details: { nav_items_count: nav_items, recommended_max: 7 },
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: [ 100 - ((nav_items - 7) * 10), 0 ].max,
            summary: "Navigation has #{nav_items} top-level items, exceeding the recommended limit of 7.",
            details: { nav_items_count: nav_items, recommended_max: 7, excess_items: nav_items - 7 },
            recommendation: "Consider consolidating menu items into broader categories or using a mega menu. Too many top-level items can overwhelm users and make it harder to find what they're looking for.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "NavItemCountTest failed: #{e.message}"
        not_applicable
      end

      protected

      def test_category
        "nav"
      end

      def has_nav_data?
        page_data&.html_content.present?
      end

      def count_top_level_nav_items
        nav = find_primary_nav
        return 0 unless nav

        # Count direct child links or list items
        top_level = nav.css(">ul>li, >a").count
        top_level = nav.css("ul>li").count if top_level == 0

        top_level
      end

      def not_applicable
        create_result(
          status: "not_applicable",
          summary: "Could not determine navigation structure"
        )
      end
    end
  end
end
