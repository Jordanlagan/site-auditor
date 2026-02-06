class CreateDynamicTestSystem < ActiveRecord::Migration[7.2]
  def change
    # Test Groups table
    create_table :test_groups do |t|
      t.string :name, null: false
      t.text :description
      t.string :color, default: "#6366f1"
      t.integer :position, default: 0
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :test_groups, :name, unique: true
    add_index :test_groups, :position

    # Dynamic Tests table
    create_table :tests do |t|
      t.references :test_group, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :test_key, null: false # unique identifier like "typos_check"

      # Test configuration
      t.text :ai_prompt, null: false # The AI prompt for evaluation
      t.jsonb :data_sources, default: [], null: false # Which data to use: ["page_content", "screenshots", "html_content", etc.]
      t.jsonb :success_conditions, default: {} # Conditions for pass/fail

      # Metadata
      t.boolean :is_core, default: false # Core tests run by default
      t.boolean :active, default: true
      t.integer :position, default: 0
      t.integer :default_priority, default: 3 # 1-5 scale

      # AI settings override (optional - falls back to audit settings)
      t.jsonb :ai_config, default: {} # model, temperature, etc.

      # Additional metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :tests, :test_key, unique: true
    add_index :tests, [ :test_group_id, :position ]
    add_index :tests, :is_core
    add_index :tests, :active
    add_index :tests, [ :test_group_id, :active ]
  end
end
