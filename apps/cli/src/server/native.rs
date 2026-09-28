use super::*;
use crate::accounts::discovery::host::{self, Report};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request {
    #[serde(default)]
    providers: Vec<Provider>,
    #[serde(default)]
    restore_removed: bool,
}

pub(super) async fn status(State(state): State<Arc<ApiState>>) -> Result<Json<Report>, ApiError> {
    let Some(vault) = state.vault.clone() else {
        return Ok(Json(Report::default()));
    };
    host::status(vault).await.map(Json).map_err(|error| {
        ApiError(
            StatusCode::SERVICE_UNAVAILABLE,
            management::account_code(&error),
        )
    })
}

pub(super) async fn start(
    State(state): State<Arc<ApiState>>,
    Extension(principal): Extension<security::Principal>,
    ApiJson(mut request): ApiJson<Request>,
) -> Result<(StatusCode, Json<Operation>), ApiError> {
    if !state.manage {
        return Err(ApiError(StatusCode::FORBIDDEN, "management_required"));
    }
    let vault = state.vault.clone().ok_or(ApiError(
        StatusCode::SERVICE_UNAVAILABLE,
        "account_storage_disabled",
    ))?;
    if request.providers.is_empty() {
        request.providers = state
            .settings
            .read()
            .await
            .values
            .tracked_providers()
            .map_err(|_| ApiError(StatusCode::BAD_REQUEST, "invalid_settings"))?;
    }
    request.providers.sort_by_key(|provider| provider.id());
    request.providers.dedup();
    let key = format!(
        "native-discovery:{}:{}",
        request.restore_removed,
        serde_json::to_string(&request.providers)
            .map_err(|_| ApiError(StatusCode::BAD_REQUEST, "invalid_request"))?
    );
    let key = principal.scoped_key(&key);
    let mut pending = state.pending.lock().await;
    if let Some(id) = pending.get(&key)
        && let Some(operation) = state.operations.lock().await.get(id)
    {
        return Ok((StatusCode::ACCEPTED, Json(operation)));
    }
    let (operation, _) = state
        .operations
        .lock()
        .await
        .start(&principal.id, "discovery", None, key.clone())
        .map_err(operation_error)?;
    pending.insert(key.clone(), operation.id.clone());
    drop(pending);
    let work = state.clone();
    let id = operation.id.clone();
    let pending_key = key.clone();
    if let Err(error) = state.spawn(async move {
        let result = scan(
            &work,
            vault,
            &request.providers,
            request.restore_removed,
            Some(&principal),
        )
        .await;
        work.operations.lock().await.finish(&id, result);
        work.pending.lock().await.remove(&key);
    }) {
        state.pending.lock().await.remove(&pending_key);
        state
            .operations
            .lock()
            .await
            .finish(&operation.id, Err("server_busy"));
        return Err(error);
    }
    Ok((StatusCode::ACCEPTED, Json(operation)))
}

async fn scan(
    state: &ApiState,
    vault: crate::accounts::vault::Vault,
    providers: &[Provider],
    restore_removed: bool,
    principal: Option<&security::Principal>,
) -> Result<Value, &'static str> {
    let _scan = state.native_scan_lock.lock().await;
    let _guard = match principal {
        Some(principal) => Some(state.client_mutation_guard(principal).await?),
        None => None,
    };
    let report = host::scan(
        vault,
        state.discovery.clone(),
        providers,
        state.context.clock.now(),
        restore_removed,
    )
    .await
    .map_err(|error| management::account_code(&error))?;
    let changed = report.registered > 0 || report.references_updated;
    let value = serde_json::to_value(&report).map_err(|_| "invalid_snapshot");
    if changed {
        state.invalidate().await;
    }
    value
}

pub(super) async fn scheduled(state: &ApiState) -> Result<(), &'static str> {
    let config = state.settings.read().await.values.clone();
    if !config.automatically_discover_logins {
        return Ok(());
    }
    let Some(vault) = state.vault.clone() else {
        return Ok(());
    };
    let providers = config.tracked_providers().map_err(|_| "invalid_settings")?;
    if !providers.is_empty() {
        scan(state, vault, &providers, false, None).await?;
    }
    Ok(())
}
