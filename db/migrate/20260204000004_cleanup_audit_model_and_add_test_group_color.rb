class CleanupAuditModelAndAddTestGroupColor < ActiveRecord::Migration[7.2]
  def change
    # Remove unnecessary fields from audits
    remove_column :audits, :overall_score, :integer
    remove_column :audits, :category_scores, :jsonb
    remove_column :audits, :raw_results, :jsonb
    remove_column :audits, :summary, :text
    remove_column :audits, :workflow_state, :string
    remove_column :audits, :discovered_pages_count, :integer
    remove_column :audits, :priority_pages_count, :integer
    remove_column :audits, :questions_answered, :integer
    remove_column :audits, :ai_decisions, :jsonb

    # Color already exists in test_groups, skip adding it
  end
end
