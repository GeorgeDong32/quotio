use crate::contract::Snapshot;
pub fn render(snapshot: &Snapshot) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(snapshot)
}
