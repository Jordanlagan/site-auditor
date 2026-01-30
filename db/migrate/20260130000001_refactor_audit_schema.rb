class RefactorAuditSchema < ActiveRecord::Migration[7.2]
  def change
    # Add audit mode
    add_column :audits, :audit_mode, :string, default: 'single_page' # single_page or full_crawl

    # Add comprehensive page data model
    create_table :page_data do |t|
      t.references :discovered_page, null: false, foreign_key: true, index: true

      # Assets
      t.jsonb :fonts, default: [] # [{family, weights, styles, urls}]
      t.jsonb :colors, default: [] # [{hex, usage_count, contexts}]
      t.jsonb :images, default: [] # [{src, alt, dimensions, format, size_bytes}]
      t.jsonb :scripts, default: [] # [{src, type, async, defer, size_bytes}]
      t.jsonb :stylesheets, default: [] # [{href, media, size_bytes}]

      # Performance
      t.integer :total_page_weight_bytes
      t.jsonb :asset_distribution # {images: bytes, scripts: bytes, css: bytes, fonts: bytes, other: bytes}
      t.jsonb :performance_metrics # {fcp, lcp, cls, fid, ttfb, tti}

      # SEO & Content
      t.jsonb :headings # {h1: [], h2: [], h3: [], h4: [], h5: [], h6: []}
      t.text :page_content # all text content
      t.jsonb :links # [{href, text, internal, rel, target}]
      t.string :meta_title
      t.text :meta_description
      t.jsonb :meta_tags # other meta tags
      t.jsonb :structured_data # JSON-LD and other structured data

      # Screenshots
      t.jsonb :screenshots # {desktop: url, mobile: url, tablet: url}

      # HTML & CSS
      t.text :html_content # full HTML for analysis
      t.text :computed_styles # relevant computed styles JSON

      # Additional metadata
      t.jsonb :metadata # viewport, lang, charset, etc.

      t.timestamps
    end

    # Test results model
    create_table :test_results do |t|
      t.references :discovered_page, null: false, foreign_key: true, index: true
      t.references :audit, null: false, foreign_key: true, index: true

      t.string :test_key, null: false # e.g., 'nav_primary_conversion_goal'
      t.string :test_category # nav, cro, design, speed, etc.
      t.string :status, null: false # passed, failed, warning, not_applicable
      t.integer :score # 0-100
      t.text :summary # brief explanation
      t.jsonb :details # detailed findings
      t.text :ai_reasoning # OpenAI's reasoning
      t.text :recommendation # what to fix
      t.integer :priority # 1-5, how important this is

      t.timestamps
    end

    # Update discovered_pages
    add_column :discovered_pages, :data_collection_status, :string, default: 'pending' # pending, collecting, complete, failed
    add_column :discovered_pages, :testing_status, :string, default: 'pending' # pending, testing, complete, failed
    add_column :discovered_pages, :is_priority_page, :boolean, default: false

    # Indexes for performance
    add_index :test_results, [ :audit_id, :test_category ]
    add_index :test_results, [ :audit_id, :status ]
    add_index :test_results, [ :discovered_page_id, :test_key ], unique: true
    add_index :discovered_pages, [ :audit_id, :is_priority_page ]
    add_index :discovered_pages, [ :audit_id, :data_collection_status ]
    add_index :discovered_pages, [ :audit_id, :testing_status ]
  end
end
