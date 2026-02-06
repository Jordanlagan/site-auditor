# Seed default test group and core tests
puts "Seeding default test group and core tests..."

# Create Default Test Group
default_group = TestGroup.find_or_create_by!(name: "Default") do |g|
  g.description = "Default tests that run on every audit"
  g.color = "#6366f1"
  g.active = true
end

puts "  ✓ Created test group: Default"

# Core Tests
core_tests = [
  {
    name: "Content Quality Check",
    test_key: "content_typos",
    description: "Checks site content for typos or grammatical errors",
    test_details: "Review the page content, headings, and meta tags for any spelling errors, grammatical mistakes, or typos. Look especially at headlines, navigation, and prominent text. Be reasonable - don't be overly pedantic about minor issues.",
    data_sources: [ "page_content", "headings", "meta_title", "meta_description" ]
  },
  {
    name: "Font Check",
    test_key: "default_fonts",
    description: "Checks if default system fonts are being used instead of custom fonts",
    test_details: "Analyze the fonts used on this page. Check if they are default system fonts (like Arial, Times New Roman, Helvetica) or if the site uses custom web fonts. Using custom fonts generally indicates more attention to design.",
    data_sources: [ "fonts", "html_content" ]
  },
  {
    name: "Internal Linking",
    test_key: "internal_links",
    description: "Checks if the page has internal links cross-linking to other pages",
    test_details: "Look for internal links on this page that connect to other pages on the same website. Good internal linking helps with SEO and user navigation. Check if links use descriptive anchor text.",
    data_sources: [ "links", "html_content", "page_content" ]
  }
]

core_tests.each do |test_data|
  test = Test.find_or_create_by!(test_key: test_data[:test_key]) do |t|
    t.test_group = default_group
    t.name = test_data[:name]
    t.description = test_data[:description]
    t.test_details = test_data[:test_details]
    t.data_sources = test_data[:data_sources]
    t.active = true
  end

  puts "    ✓ Created test: #{test.name} (#{test.test_key})"
end

puts "\n✓ Seeding complete!"
puts "  Test Groups: #{TestGroup.count}"
puts "  Total Tests: #{Test.count}"
