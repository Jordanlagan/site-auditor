class SimplifyTestSystem < ActiveRecord::Migration[7.2]
  def change
    # Remove complex columns from tests
    remove_column :tests, :position, :integer
    remove_column :tests, :default_priority, :integer
    remove_column :tests, :is_core, :boolean
    remove_column :tests, :ai_config, :jsonb
    remove_column :tests, :success_conditions, :jsonb
    remove_column :tests, :metadata, :jsonb

    # Rename ai_prompt to test_details
    rename_column :tests, :ai_prompt, :test_details

    # Remove indices we don't need
    remove_index :tests, name: "index_tests_on_test_group_id_and_position" if index_exists?(:tests, [ :test_group_id, :position ])
    remove_index :tests, name: "index_tests_on_is_core" if index_exists?(:tests, :is_core)
    remove_index :tests, name: "index_tests_on_test_group_id_and_active" if index_exists?(:tests, [ :test_group_id, :active ])

    # Simplify test_results
    remove_column :test_results, :score, :integer
    remove_column :test_results, :ai_reasoning, :text
    remove_column :test_results, :recommendation, :text
    remove_column :test_results, :priority, :integer
    remove_column :test_results, :details, :jsonb

    # Remove position from test_groups
    remove_column :test_groups, :position, :integer
    remove_column :test_groups, :metadata, :jsonb
  end
end
