module Tests
  module V1
    class SpeedLazyLoadingTest < BaseTest
      def run!
        return not_applicable unless page_data&.images.present?

        lazy_loaded_images = page_data.images.count { |img| img["loading"] == "lazy" }
        total_images = page_data.images.size

        return not_applicable if total_images == 0

        percentage = (lazy_loaded_images.to_f / total_images * 100).round

        if percentage >= 70
          create_result(
            status: "passed",
            score: 100,
            summary: "#{percentage}% of images use lazy loading (#{lazy_loaded_images}/#{total_images}).",
            details: {
              lazy_loaded_count: lazy_loaded_images,
              total_images: total_images,
              percentage: percentage
            },
            priority: 3
          )
        elsif percentage >= 30
          create_result(
            status: "warning",
            score: 60,
            summary: "Only #{percentage}% of images use lazy loading (#{lazy_loaded_images}/#{total_images}).",
            details: {
              lazy_loaded_count: lazy_loaded_images,
              total_images: total_images,
              percentage: percentage
            },
            recommendation: 'Implement lazy loading for below-the-fold images to improve initial page load performance. Add loading="lazy" attribute to img tags.',
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 20,
            summary: "Only #{percentage}% of images use lazy loading (#{lazy_loaded_images}/#{total_images}).",
            details: {
              lazy_loaded_count: lazy_loaded_images,
              total_images: total_images,
              percentage: percentage
            },
            recommendation: 'Implement lazy loading for all below-the-fold images. This will significantly improve initial page load time. Add loading="lazy" to img tags or use a JavaScript library.',
            priority: 4
          )
        end
      rescue => e
        Rails.logger.error "SpeedLazyLoadingTest failed: #{e.message}"
        not_applicable
      end

      protected

      def test_category
        "speed"
      end

      def not_applicable
        create_result(
          status: "not_applicable",
          summary: "No images found to analyze"
        )
      end
    end
  end
end
