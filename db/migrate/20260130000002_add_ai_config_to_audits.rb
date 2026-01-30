class AddAiConfigToAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :audits, :ai_config, :jsonb, default: {}
  end
end
