use super::*;
use crate::accounts::{AccountError, clients};
use axum::Extension;

fn owner(principal: &security::Principal) -> Result<(), ApiError> {
    if principal.owner {
        Ok(())
    } else {
        Err(ApiError(StatusCode::FORBIDDEN, "owner_required"))
    }
}
fn vault(state: &ApiState) -> Result<crate::accounts::vault::Vault, ApiError> {
    state
        .vault
        .clone()
        .filter(|_| !state.no_saved_accounts)
        .ok_or(ApiError(
            StatusCode::SERVICE_UNAVAILABLE,
            "account_storage_disabled",
        ))
}
fn failure(error: AccountError) -> ApiError {
    match error {
        AccountError::Input | AccountError::Label => {
            ApiError(StatusCode::BAD_REQUEST, "invalid_client_request")
        }
        _ => ApiError(
            StatusCode::SERVICE_UNAVAILABLE,
            management::account_code(&error),
        ),
    }
}

pub(super) async fn list(
    State(state): State<Arc<ApiState>>,
    Extension(principal): Extension<security::Principal>,
) -> Result<Json<Value>, ApiError> {
    owner(&principal)?;
    let clients = clients::list(vault(&state)?, state.context.clock.now())
        .await
        .map_err(failure)?;
    Ok(Json(json!({"schema_version":2,"clients":clients})))
}

pub(super) async fn create(
    State(state): State<Arc<ApiState>>,
    Extension(principal): Extension<security::Principal>,
    ApiJson(input): ApiJson<clients::Create>,
) -> Result<(StatusCode, Json<clients::Created>), ApiError> {
    owner(&principal)?;
    if input.scope != clients::Scope::Read {
        return Err(ApiError(
            StatusCode::BAD_REQUEST,
            "unsupported_client_scope",
        ));
    }
    if !state.manage {
        return Err(ApiError(StatusCode::METHOD_NOT_ALLOWED, "read_only"));
    }
    let _guard = crate::accounts::service::mutation_guard(&state.commit_guard)
        .await
        .map_err(failure)?;
    let created = clients::create(vault(&state)?, input, state.context.clock.now())
        .await
        .map_err(failure)?;
    Ok((StatusCode::CREATED, Json(created)))
}

pub(super) async fn revoke(
    State(state): State<Arc<ApiState>>,
    Extension(principal): Extension<security::Principal>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    owner(&principal)?;
    if !state.manage {
        return Err(ApiError(StatusCode::METHOD_NOT_ALLOWED, "read_only"));
    }
    let _guard = crate::accounts::service::mutation_guard(&state.commit_guard)
        .await
        .map_err(failure)?;
    clients::revoke(vault(&state)?, id.clone())
        .await
        .map_err(failure)?;
    drop(_guard);
    if let Some(manager) = &state.oauth {
        manager.cancel_owner(&id).await;
    }
    Ok(StatusCode::NO_CONTENT)
}
