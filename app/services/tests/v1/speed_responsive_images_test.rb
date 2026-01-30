module Tests
  module V1
    class SpeedResponsiveImagesTest < BaseTest
      def run!
        return not_applicable(summary: "No image data available") unless page_data&.images.present?

        images = page_data.images
        images_with_srcset = images.count { |img| img["srcset"].present? }
        total_images = images.count

        percentage = (images_with_srcset.to_f / total_images * 100).round

        if percentage >= 80
          create_result(
            status: "passed",
            score: 100,
            summary: "#{percentage}% of images use responsive srcset.",
            details: { responsive_count: images_with_srcset, total_images: total_images, percentage: percentage },
            priority: 3
          )
        elsif percentage >= 50
          create_result(
            status: "warning",
            score: 70,
            summary: "Only #{percentage}% of images use responsive srcset.",
            details: { responsive_count: images_with_srcset, total_images: total_images, percentage: percentage },
            recommendation: "Add srcset attributes to more images to serve appropriately sized images for different screens.",
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 40,
            summary: "Only #{percentage}% of images use responsive srcset.",
            details: { responsive_count: images_with_srcset, total_images: total_images, percentage: percentage },
            recommendation: "Implement responsive images using srcset and sizes attributes. This significantly improves mobile performance.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "SpeedResponsiveImagesTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze responsive images")
      end

      protected

      def test_category
        "speed"
      end
    end
  end
end
