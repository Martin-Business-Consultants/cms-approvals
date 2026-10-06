# frozen_string_literal: true

class CreateApprovalsChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :approvals_changes do |t|
      t.string :action, null: false
      t.string :subject_type, null: false
      t.integer :subject_id
      t.integer :collection_id
      t.string :prefix, null: false
      t.json :payload, null: false, default: {}
      t.json :base, null: false, default: {}
      t.datetime :base_updated_at
      t.string :state, null: false, default: "pending"
      t.string :proposed_by
      t.references :proposer, foreign_key: {to_table: :users, on_delete: :nullify}
      t.references :decided_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.datetime :decided_at
      t.timestamps
    end
    add_index :approvals_changes, :state
    add_index :approvals_changes, [:subject_type, :subject_id]
  end
end
