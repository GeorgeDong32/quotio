//! Revocable host-client credentials. Only their host-bound digest is persisted.
use super::{AccountError, Document, random_string, validate_label, vault::Vault};
use ring::hmac;
use serde::{Deserialize, Serialize};
use time::OffsetDateTime;

const MAX_CLIENTS: usize = 64;
const MAX_LIFETIME: u64 = 365 * 24 * 60 * 60;
fn default_lifetime() -> u64 {
    30 * 24 * 60 * 60
}

#[derive(Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Scope {
    #[default]
    Read,
    Manage,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Record {
    label: String,
    scope: Scope,
    digest: String,
    #[serde(with = "time::serde::rfc3339")]
    created_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    expires_at: OffsetDateTime,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Create {
    pub label: String,
    #[serde(default)]
    pub scope: Scope,
    #[serde(default = "default_lifetime")]
    pub expires_in_seconds: u64,
}

#[derive(Serialize)]
pub(crate) struct Info {
    pub id: String,
    pub label: String,
    pub scope: Scope,
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
}
#[derive(Serialize)]
pub(crate) struct Created {
    pub schema_version: u32,
    pub host_id: String,
    pub client: Info,
    pub token: String,
}

pub(crate) fn valid(document: &Document) -> bool {
    document.client_grants.len() <= MAX_CLIENTS
        && (document.client_grants.is_empty() || document.resolved.is_some())
        && document.client_grants.iter().all(|(id, record)| {
            crate::contract::valid_id(id)
                && id != "owner"
                && id != "anonymous"
                && validate_label(&record.label).ok().as_ref() == Some(&record.label)
                && record.digest.len() == 64
                && record.digest.bytes().all(|c| c.is_ascii_hexdigit())
                && record.created_at < record.expires_at
                && (record.expires_at - record.created_at).whole_seconds() <= MAX_LIFETIME as i64
        })
}
pub(crate) fn has_manage_grants(document: &Document) -> bool {
    document
        .client_grants
        .values()
        .any(|record| record.scope == Scope::Manage)
}

pub(crate) async fn can_manage(
    vault: Vault,
    id: &str,
    now: OffsetDateTime,
) -> Result<bool, AccountError> {
    let tx = super::service::begin(vault).await?;
    Ok(tx.document.client_grants.get(id).is_some_and(|record| {
        record.scope == Scope::Manage && now >= record.created_at && now < record.expires_at
    }))
}

fn digest(host: &str, token: &str) -> String {
    crate::cache::fingerprint(&["quotio-host-client", host, token])
}
fn info(id: &str, record: &Record) -> Info {
    Info {
        id: id.into(),
        label: record.label.clone(),
        scope: record.scope,
        expires_at: record.expires_at,
    }
}

pub(crate) async fn create(
    vault: Vault,
    input: Create,
    now: OffsetDateTime,
) -> Result<Created, AccountError> {
    let label = validate_label(&input.label)?;
    if !(1..=MAX_LIFETIME).contains(&input.expires_in_seconds) {
        return Err(AccountError::Input);
    }
    tokio::task::spawn_blocking(move || {
        let mut tx = vault.begin()?;
        tx.document.enable_resolved_accounts()?;
        tx.document
            .client_grants
            .retain(|_, record| record.expires_at > now);
        if tx.document.client_grants.len() >= MAX_CLIENTS {
            return Err(AccountError::Input);
        }
        let host_id = tx
            .document
            .resolved
            .as_ref()
            .expect("initialized")
            .host_id
            .clone();
        let id = random_string()?;
        let token = format!("qclient.{id}.{}", random_string()?);
        let record = Record {
            label,
            scope: input.scope,
            digest: digest(&host_id, &token),
            created_at: now,
            expires_at: now
                .checked_add(time::Duration::seconds(input.expires_in_seconds as i64))
                .ok_or(AccountError::Input)?,
        };
        let client = info(&id, &record);
        tx.document.client_grants.insert(id, record);
        tx.commit()?;
        Ok(Created {
            schema_version: 2,
            host_id,
            client,
            token,
        })
    })
    .await
    .map_err(|_| AccountError::Storage)?
}

pub(crate) async fn list(vault: Vault, now: OffsetDateTime) -> Result<Vec<Info>, AccountError> {
    tokio::task::spawn_blocking(move || {
        let tx = vault.begin()?;
        Ok(tx
            .document
            .client_grants
            .iter()
            .filter(|(_, record)| record.expires_at > now)
            .map(|(id, record)| info(id, record))
            .collect())
    })
    .await
    .map_err(|_| AccountError::Storage)?
}

pub(crate) async fn revoke(vault: Vault, id: String) -> Result<(), AccountError> {
    tokio::task::spawn_blocking(move || {
        let mut tx = vault.begin()?;
        if tx.document.client_grants.remove(&id).is_some() {
            tx.commit()?;
        }
        Ok(())
    })
    .await
    .map_err(|_| AccountError::Storage)?
}

pub(crate) async fn authenticate(
    vault: Vault,
    token: String,
    now: OffsetDateTime,
) -> Result<Option<Info>, AccountError> {
    let Some((id, secret)) = token
        .strip_prefix("qclient.")
        .and_then(|value| value.split_once('.'))
    else {
        return Ok(None);
    };
    if !crate::contract::valid_id(id)
        || !crate::contract::valid_id(secret)
        || id.len() != 43
        || secret.len() != 43
    {
        return Ok(None);
    }
    let id = id.to_owned();
    tokio::task::spawn_blocking(move || {
        let tx = vault.begin()?;
        let Some(record) = tx.document.client_grants.get(&id) else {
            return Ok(None);
        };
        if now < record.created_at || now >= record.expires_at {
            return Ok(None);
        }
        let host = &tx
            .document
            .resolved
            .as_ref()
            .ok_or(AccountError::Corrupt)?
            .host_id;
        let candidate = hmac::Key::new(hmac::HMAC_SHA256, digest(host, &token).as_bytes());
        let key = hmac::Key::new(hmac::HMAC_SHA256, record.digest.as_bytes());
        let proof = hmac::sign(&candidate, b"quotio-client-authentication");
        Ok(
            hmac::verify(&key, b"quotio-client-authentication", proof.as_ref())
                .is_ok()
                .then(|| info(&id, record)),
        )
    })
    .await
    .map_err(|_| AccountError::Storage)?
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::accounts::vault::{Backend, tests::Memory};
    use std::sync::Arc;

    #[tokio::test]
    async fn credentials_survive_restart_expire_revoke_and_reject_another_host() {
        let directory = std::env::temp_dir().join(random_string().unwrap());
        let memory = Arc::new(Memory::default());
        let vault = Vault::new(memory.clone(), directory.join("lock"));
        let now = time::macros::datetime!(2026-09-26 0:00 UTC);
        let created = create(
            vault.clone(),
            Create {
                label: "Phone".into(),
                scope: Scope::Read,
                expires_in_seconds: 60,
            },
            now,
        )
        .await
        .unwrap();
        let bytes = memory.read().unwrap().unwrap();
        assert!(!String::from_utf8_lossy(&bytes).contains(&created.token));
        let restarted = Vault::new(memory.clone(), directory.join("lock"));
        assert_eq!(
            authenticate(restarted.clone(), created.token.clone(), now)
                .await
                .unwrap()
                .unwrap()
                .id,
            created.client.id
        );
        assert!(
            authenticate(
                restarted.clone(),
                created.token.clone(),
                now + time::Duration::seconds(60)
            )
            .await
            .unwrap()
            .is_none()
        );
        assert!(
            authenticate(restarted.clone(), created.token.clone() + "invalid", now)
                .await
                .unwrap()
                .is_none()
        );
        let mut value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["version"], 17);
        value["version"] = 16.into();
        memory.write(&serde_json::to_vec(&value).unwrap()).unwrap();
        assert!(matches!(vault.begin(), Err(AccountError::Corrupt)));
        memory.write(&bytes).unwrap();
        let mut tx = vault.begin().unwrap();
        tx.document.resolved.as_mut().unwrap().host_id = random_string().unwrap();
        tx.commit().unwrap();
        assert!(
            authenticate(vault.clone(), created.token.clone(), now)
                .await
                .unwrap()
                .is_none()
        );
        memory.write(&bytes).unwrap();
        revoke(vault.clone(), created.client.id.clone())
            .await
            .unwrap();
        revoke(vault.clone(), created.client.id).await.unwrap();
        assert!(
            authenticate(vault.clone(), created.token, now)
                .await
                .unwrap()
                .is_none()
        );
        assert!(list(vault, now).await.unwrap().is_empty());
        std::fs::remove_dir_all(directory).unwrap();
    }
}
