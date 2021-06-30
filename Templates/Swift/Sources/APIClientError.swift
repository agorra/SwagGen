{% include "Includes/Header.stencil" %}

import Foundation

public enum APIClientError: Error {

    case requestError(RequestError)
    case responseError(ResponseError, statusCode: Int? = nil, data: Data? = nil)

    public enum RequestError {
        case encodingError(Error)
        case validationError(Error)
    }
    public enum ResponseError {
        case emptyResponse
        case unexpectedStatusCode
        case decodingError(DecodingError)
        case networkError(Error)
    }
}

extension APIClientError: CustomStringConvertible {

    public var name: String {
        switch self {
        case .requestError(.validationError):
            return "Request validation failed"
        case .requestError(.encodingError):
            return "Request encoding failed"
        case .responseError(.emptyResponse, _, _):
            return "Empty response"
        case .responseError(.unexpectedStatusCode, _, _):
            return "Unexpected status code"
        case .responseError(.decodingError, _, _):
            return "Decoding error"
        case .responseError(.networkError, _, _):
            return "Network error"
        }
    }

    public var description: String {
        switch self {
        case .requestError(.validationError(let error)):
            return "\(name): \(error.localizedDescription)"
        case .requestError(.encodingError(let error)):
            return "\(name): \(error.localizedDescription)"
        case .responseError(.emptyResponse, _, _):
            return "\(name)"
        case .responseError(.unexpectedStatusCode, let code, _):
            return "\(name): \(code?.description ?? "–")"
        case .responseError(.decodingError(let error), _, _):
            return "\(name): \(error.localizedDescription)"
        case .responseError(.networkError(let error), _, _):
            return "\(name): \(error.localizedDescription)"
        }
    }
}
