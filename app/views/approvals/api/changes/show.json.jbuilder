json.approval do
  json.partial! "approvals/api/changes/change", change: @change
  json.payload @change.payload
end
