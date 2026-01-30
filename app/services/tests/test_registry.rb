module Tests
  class TestRegistry
    # Registry of all V1 tests (ready to run)
    V1_TESTS = {
      # Navigation Tests (2 - only super verifiable)
      nav_item_count: "Tests::V1::NavItemCountTest",
      nav_sticky_accessible: "Tests::V1::NavStickyAccessibleTest",

      # Structure Tests (8)
      structure_search_bar: "Tests::V1::StructureSearchBarTest",
      structure_logo_links_home: "Tests::V1::StructureLogoLinksHomeTest",
      structure_url_hierarchy: "Tests::V1::StructureUrlHierarchyTest",
      structure_content_flow: "Tests::V1::StructureContentFlowTest",
      structure_reading_level: "Tests::V1::StructureReadingLevelTest",
      structure_copy_readable: "Tests::V1::StructureCopyReadableTest",
      structure_brand_inference: "Tests::V1::StructureBrandInferenceTest",
      structure_typos: "Tests::V1::StructureTyposTest",

      # CRO Tests (14)
      cro_above_fold_elements: "Tests::V1::CroAboveFoldElementsTest",
      cro_primary_cta_obvious: "Tests::V1::CroPrimaryCtaObviousTest",
      cro_cta_above_fold: "Tests::V1::CroCtaAboveFoldTest",
      cro_cta_stand_out: "Tests::V1::CroCtaStandOutTest",
      cro_forms_simple: "Tests::V1::CroFormsSimpleTest",
      cro_free_shipping: "Tests::V1::CroFreeShippingTest",
      cro_discounts_promotions: "Tests::V1::CroDiscountsPromotionsTest",
      cro_reviews_testimonials: "Tests::V1::CroReviewsTestimonialsTest",
      cro_faqs: "Tests::V1::CroFaqsTest",
      cro_usps_present: "Tests::V1::CroUspsPresentTest",
      cro_policy_pages: "Tests::V1::CroPolicyPagesTest",
      cro_guarantees: "Tests::V1::CroGuaranteesTest",
      cro_purchase_steps_clear: "Tests::V1::CroPurchaseStepsClearTest",
      cro_policy_statements_plain: "Tests::V1::CroPolicyStatementsPlainTest",

      # Design Tests (5)
      design_mobile_responsive: "Tests::V1::DesignMobileResponsiveTest",
      design_tap_target_size: "Tests::V1::DesignTapTargetSizeTest",
      design_visual_consistency: "Tests::V1::DesignVisualConsistencyTest",
      design_high_quality_images: "Tests::V1::DesignHighQualityImagesTest",
      design_outdated_elements: "Tests::V1::DesignOutdatedElementsTest",

      # Reviews Tests (3)
      reviews_aggregate_structured_data: "Tests::V1::ReviewsAggregateStructuredDataTest",
      reviews_aggregate_rating_visible: "Tests::V1::ReviewsAggregateRatingVisibleTest",
      reviews_third_party_badges: "Tests::V1::ReviewsThirdPartyBadgesTest",

      # Price Tests (3)
      price_clearly_visible: "Tests::V1::PriceClearlyVisibleTest",
      price_value_messaging: "Tests::V1::PriceValueMessagingTest",
      price_discount_labels: "Tests::V1::PriceDiscountLabelsTest",

      # Speed Tests (5)
      speed_page_speed_score: "Tests::V1::SpeedPageSpeedScoreTest",
      speed_lazy_loading: "Tests::V1::SpeedLazyLoadingTest",
      speed_responsive_images: "Tests::V1::SpeedResponsiveImagesTest",
      speed_deferred_scripts: "Tests::V1::SpeedDeferredScriptsTest",
      speed_no_bloat: "Tests::V1::SpeedNoBloatTest"
    }.freeze

    # V2 tests (not yet implemented)
    V2_TESTS = {
      # Will be implemented in future versions
    }.freeze

    def self.all_v1_tests
      V1_TESTS.keys
    end

    def self.all_v2_tests
      V2_TESTS.keys
    end

    def self.get_test_class(test_key)
      class_name = V1_TESTS[test_key.to_sym] || V2_TESTS[test_key.to_sym]
      return nil unless class_name

      class_name.constantize
    rescue NameError => e
      Rails.logger.error "Test class not found: #{class_name} - #{e.message}"
      nil
    end

    def self.tests_by_category(category)
      all_v1_tests.select do |test_key|
        test_class = get_test_class(test_key)
        next false unless test_class

        # Create a temporary instance to get the category
        test_instance = test_class.allocate
        test_instance.instance_variable_set(:@discovered_page, OpenStruct.new(url: ""))
        test_instance.send(:test_category) == category
      rescue
        false
      end
    end
  end
end
