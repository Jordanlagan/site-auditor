class CreateAuditWorkflowTables < ActiveRecord::Migration[7.2]
  def change
    # Discovered pages during crawl
    create_table :discovered_pages do |t|
      t.references :audit, null: false, foreign_key: true
      t.string :url, null: false
      t.string :page_type # homepage, product, pricing, checkout, etc.
      t.integer :priority_score # AI-calculated importance
      t.string :status, default: 'pending' # pending, analyzing, complete, skipped
      t.jsonb :crawl_metadata # depth, links_to, linked_from, etc.
      t.timestamps
    end

    # Screenshots captured during audit
    create_table :page_screenshots do |t|
      t.references :discovered_page, null: false, foreign_key: true
      t.string :device_type # desktop, mobile
      t.string :screenshot_url # S3 or local path
      t.integer :viewport_width
      t.integer :viewport_height
      t.jsonb :metadata # above_fold_height, detected_elements, etc.
      t.timestamps
    end

    # Interactive questions asked to user
    create_table :audit_questions do |t|
      t.references :audit, null: false, foreign_key: true
      t.references :discovered_page, foreign_key: true
      t.string :question_type # cta_identification, page_purpose, competing_actions
      t.text :question_text
      t.jsonb :options # For multiple choice questions
      t.text :user_response
      t.string :status, default: 'pending' # pending, answered, skipped
      t.timestamps
    end

    # Adaptive test results
    create_table :adaptive_tests do |t|
      t.references :discovered_page, null: false, foreign_key: true
      t.string :test_type # contrast_check, cta_prominence, typography_scan, etc.
      t.string :decision_reason # Why this test was chosen
      t.jsonb :results
      t.integer :impact_score # 1-100
      t.timestamps
    end

    # Add workflow state to audits
    add_column :audits, :workflow_state, :string, default: 'initializing'
    add_column :audits, :current_phase, :string # crawling, prioritizing, questioning, analyzing, synthesizing
    add_column :audits, :discovered_pages_count, :integer, default: 0
    add_column :audits, :priority_pages_count, :integer, default: 0
    add_column :audits, :questions_answered, :integer, default: 0
    add_column :audits, :ai_decisions, :jsonb, default: {}

    add_index :discovered_pages, [ :audit_id, :page_type ]
    add_index :discovered_pages, [ :audit_id, :priority_score ]
    add_index :audit_questions, [ :audit_id, :status ]
  end
end
