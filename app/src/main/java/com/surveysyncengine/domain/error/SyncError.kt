package com.surveysyncengine.domain.error

import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

// ---------------------------------------------------------------------------
// SyncError — unified error model that abstracts over network/server/local
// failures. Callers use this to decide whether to retry or surface to user.
// ---------------------------------------------------------------------------

sealed class SyncError {

    // Network is genuinely down — stop syncing to conserve battery
    data class NetworkUnavailable(val cause: Throwable) : SyncError()

    // Request timed out — network likely degraded, treat as network failure
    data class Timeout(val cause: Throwable) : SyncError()

    // Server rejected the payload — retrying won't help without data fix
    data class ClientError(val httpCode: Int, val serverMessage: String) : SyncError()

    // Server-side failure — may be transient, retry with backoff
    data class ServerError(val httpCode: Int, val serverMessage: String) : SyncError()

    // Anything else — log and treat cautiously
    data class Unknown(val cause: Throwable) : SyncError()

    // Convenience
    fun isNetworkLevel(): Boolean =
        this is NetworkUnavailable || this is Timeout

    fun isRetryable(): Boolean =
        this is NetworkUnavailable || this is Timeout || this is ServerError

    fun userFacingMessage(): String = when (this) {
        is NetworkUnavailable -> "No internet connection."
        is Timeout -> "Connection timed out."
        is ClientError -> "Response rejected by server ($httpCode)."
        is ServerError -> "Server error ($httpCode). Will retry."
        is Unknown -> "Unexpected error: ${cause.message}"
    }
}

// ---------------------------------------------------------------------------
// Extension — maps any Throwable to the SyncError hierarchy.
// HttpException is an interface here so we stay framework-agnostic in domain;
// actual mapping for Retrofit's HttpException lives in the data layer adapter.
// ---------------------------------------------------------------------------

fun Throwable.toSyncError(): SyncError = when (this) {
    is UnknownHostException  -> SyncError.NetworkUnavailable(this)
    is ConnectException      -> SyncError.NetworkUnavailable(this)
    is SocketTimeoutException -> SyncError.Timeout(this)
    is kotlinx.coroutines.TimeoutCancellationException -> SyncError.Timeout(this)
    is SurveyHttpException -> when {
        httpCode in 400..499 -> SyncError.ClientError(httpCode, message ?: "")
        httpCode in 500..599 -> SyncError.ServerError(httpCode, message ?: "")
        else                 -> SyncError.Unknown(this)
    }
    else -> SyncError.Unknown(this)
}

// ---------------------------------------------------------------------------
// SurveyHttpException — thin domain wrapper so we don't leak Retrofit into
// domain. The data layer catches Retrofit's HttpException and re-throws this.
// ---------------------------------------------------------------------------
class SurveyHttpException(
    val httpCode: Int,
    override val message: String,
) : Exception(message)
