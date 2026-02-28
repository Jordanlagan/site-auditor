class AddDetailsToTestResultsAndAiSummaryToAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :test_results, :details, :jsonb, default: []
    add_column :audits, :ai_summary, :text
  end
end
