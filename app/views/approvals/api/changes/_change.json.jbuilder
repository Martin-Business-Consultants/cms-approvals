json.extract! change, :id, :action, :state, :summary, :proposed_by, :created_at, :decided_at
json.subject do
  json.type change.subject_type
  json.id change.subject_id
end
json.changed change.changed_fields.map(&:name)
json.path "/approvals/#{change.id}"
