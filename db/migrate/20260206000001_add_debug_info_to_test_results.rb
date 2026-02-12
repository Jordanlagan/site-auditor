class AddDebugInfoToTestResults < ActiveRecord::Migration[7.2]
  def change
    add_column :test_results, :ai_prompt, :text
    add_column :test_results, :data_context, :jsonb, default: {}
    add_column :test_results, :ai_response, :text
  end
end
