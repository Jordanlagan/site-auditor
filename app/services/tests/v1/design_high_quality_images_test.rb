module Tests
  module V1
    class DesignHighQualityImagesTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.images.present?

        images = page_data.images

        analyze_with_ai(
          "Does the site use relevant, high quality images?",
          {
            image_count: images.count,
            sample_images: images.first(10).map { |img| { src: img["src"], dimensions: "#{img['width']}×#{img['height']}", alt: img["alt"] } },
            analysis_points: [
              "Are images high resolution?",
              "Do images look professional?",
              "Are images relevant to content?",
              "Are stock photos avoided or used tastefully?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "DesignHighQualityImagesTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze image quality")
      end

      protected

      def test_category
        "design"
      end
    end
  end
end
