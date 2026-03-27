//
//  SyncError.swift
//  SurveySyncEngineIOS
//
//
import Foundation

// MARK: - 1. Domain HTTP Exception Wrapper
/// A custom error type to capture specific HTTP status codes and messages from the server.
public struct SurveyHttpException: Error {
    public let httpCode: Int
    public let message: String
    
    public init(httpCode: Int, message: String) {
        self.httpCode = httpCode
        self.message = message
    }
}

// MARK: - 2. Sync Error (Sealed Class Equivalent)
/// A high-level enumeration representing the categorized errors that can occur during synchronization.
public enum SyncError: Error {
    case networkUnavailable(Error)
    case timeout(Error)
    case clientError(httpCode: Int, serverMessage: String)
    case serverError(httpCode: Int, serverMessage: String)
    case unknown(Error)

    // MARK: - Test Helpers
    // Booleans to simplify unit testing assertions (e.g., XCTAssertTrue(error.isTimeout))
    
    public var isNetworkUnavailable: Bool {
        if case .networkUnavailable = self { return true }
        return false
    }

    public var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }

    public var isClientError: Bool {
        if case .clientError = self { return true }
        return false
    }

    public var isServerError: Bool {
        if case .serverError = self { return true }
        return false
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
    
    // MARK: - Convenience Methods
    
    /// Checks if the error occurred at the connection level (connectivity or latency).
    public func isNetworkLevel() -> Bool {
        switch self {
        case .networkUnavailable(_), .timeout(_):
            return true
        default:
            return false
        }
    }

    /// Determines if the Sync Engine should attempt to retry the operation based on the error type.
    public func isRetryable() -> Bool {
        switch self {
        case .networkUnavailable, .timeout, .serverError:
            return true
        default:
            // Client errors (4xx) are usually not retryable without changes to the request.
            return false
        }
    }

    /// Provides a localized, user-friendly string to be displayed in the UI.
    public func userFacingMessage() -> String {
        switch self {
        case .networkUnavailable:
            return "No internet connection."
        case .timeout:
            return "Connection timed out."
        case .clientError(let code, _):
            return "Response rejected by server (\(code))."
        case .serverError(let code, _):
            return "Server error (\(code)). Will retry."
        case .unknown(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}

extension SyncError: Equatable {
    /// Extracts the HTTP code if the error is a client or server-side response error.
    var httpCode: Int? {
        switch self {
        case let .clientError(code, _),
             let .serverError(code, _):
            return code
        default:
            return nil
        }
    }

    /// Implementation of the Equatable protocol to allow comparison of SyncError cases.
    public static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable),
             (.timeout, .timeout):
            return true
            
        case (.clientError(let lCode, let lMsg), .clientError(let rCode, let rMsg)),
             (.serverError(let lCode, let lMsg), .serverError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
            
        case (.unknown(let lErr), .unknown(let rErr)):
            // Fallback to description comparison for unknown underlying errors
            return lErr.localizedDescription == rErr.localizedDescription
            
        default:
            return false
        }
    }
}

// MARK: - 3. Error Mapping Extension
public extension Error {
   
    /// Maps generic Swift/iOS Errors into the domain-specific SyncError enum.
    func toSyncError() -> SyncError {
        // Return immediately if the error is already the correct type
        if let syncError = self as? SyncError {
            return syncError
        }
        
        // Convert HTTP-specific exceptions into Client (4xx) or Server (5xx) errors
        if let httpException = self as? SurveyHttpException {
            switch httpException.httpCode {
            case 400...499:
                return .clientError(httpCode: httpException.httpCode, serverMessage: httpException.message)
            case 500...599:
                return .serverError(httpCode: httpException.httpCode, serverMessage: httpException.message)
            default:
                return .unknown(self)
            }
        }
        
        // Map native Apple URLErrors to corresponding sync cases
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
                return .networkUnavailable(urlError)
            case .timedOut:
                return .timeout(urlError)
            default:
                return .unknown(urlError)
            }
        }
        
        // Handle Task cancellations (Swift Concurrency) as timeouts for retry purposes
        if self is CancellationError {
            return .timeout(self)
        }
        
        return .unknown(self)
    }
}
