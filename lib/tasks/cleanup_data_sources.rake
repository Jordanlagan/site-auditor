namespace :tests do
  desc "Update all tests to use standardized data source names"
  task cleanup_data_sources: :environment do
    # Mapping of old data source names to new standardized names
    mapping = {
      "html_content" => "page_html",
      "scripts" => "asset_urls",
      "fonts" => "asset_urls",
      "images" => "asset_urls",
      "stylesheets" => "asset_urls",
      "performance_metrics" => "performance_data",
      "asset_distribution" => "performance_data",
      "total_page_weight" => "performance_data",
      "links" => "internal_links",  # Assuming internal links by default
      "meta_tags" => "page_html",
      "meta_title" => "page_html",
      "meta_description" => "page_html",
      "structured_data" => "page_html",
      "computed_styles" => "page_html"
    }

    updated_count = 0
    Test.find_each do |test|
      original_sources = test.data_sources.dup
      updated_sources = test.data_sources.map { |source| mapping[source] || source }.uniq

      if original_sources != updated_sources
        test.update!(data_sources: updated_sources)
        puts "Updated Test ##{test.id} (#{test.name})"
        puts "  Old: #{original_sources.inspect}"
        puts "  New: #{updated_sources.inspect}"
        updated_count += 1
      end
    end

    puts "\n✅ Updated #{updated_count} tests"

    # Show final stats
    puts "\nFinal data sources in use:"
    all_sources = Test.pluck(:data_sources).flatten.uniq.sort
    all_sources.each do |source|
      count = Test.where("data_sources @> ARRAY[?]::varchar[]", source).count
      puts "  - #{source}: #{count} tests"
    end
  end
end
