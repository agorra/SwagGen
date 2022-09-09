{% include "Includes/Header.stencil" %}

import Foundation
import Alamofire

/// Manages and sends APIRequests
public class APIClient {

    public static var `default` = APIClient(baseURL: {% if options.baseURL %}"{{ options.baseURL }}"{% elif defaultServer %}{{ options.name }}.Server.{{ defaultServer.name }}{% else %}""{% endif %})

    /// A list of RequestBehaviours that can be used to monitor and alter all requests
    public var behaviours: [RequestBehaviour] = []

    /// The base url prepended before every request path
    public var baseURL: String

    /// The Alamofire session used for each request
    public var session: Session

    /// These headers will get added to every request
    public var defaultHeaders: [String: String]

    /// HTTP response codes for which empty response bodies are considered appropriate. `[204, 205]` by default.
    public var emptyResponseCodes: Set<Int>

    /// HTTP response codes for which response are considered success. `200..<300` by default
    public var acceptableStatusCodes: Range<Int>

    public var jsonDecoder = JSONDecoder()
    public var jsonEncoder = JSONEncoder()

    public var decodingQueue = DispatchQueue(label: "apiClient", qos: .utility, attributes: .concurrent)

    public init(
        baseURL: String, 
        session: Session = .default, 
        defaultHeaders: [String: String] = [:], 
        behaviours: [RequestBehaviour] = [], 
        emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
        acceptableStatusCodes: Range<Int> = 200..<300
    ) {
        self.baseURL = baseURL
        self.session = session
        self.behaviours = behaviours
        self.defaultHeaders = defaultHeaders
        self.emptyResponseCodes = emptyResponseCodes
        self.acceptableStatusCodes = acceptableStatusCodes
        jsonDecoder.dateDecodingStrategy = .custom(dateDecoder)
        jsonEncoder.dateEncodingStrategy = .formatted({{ options.name }}.dateEncodingFormatter)
    }

    /// Makes a network request
    ///
    /// - Parameters:
    ///   - request: The API request to make
    ///   - behaviours: A list of behaviours that will be run for this request. Merged with APIClient.behaviours
    ///   - completionQueue: The queue that complete will be called on
    ///   - complete: A closure that gets passed the APIResponse
    /// - Returns: A cancellable request. Not that cancellation will only work after any validation RequestBehaviours have run
    @discardableResult
    public func makeRequest<T>(
        _ request: APIRequest<T>, 
        behaviours: [RequestBehaviour] = [], 
        interceptor: RequestInterceptor? = nil,
        completionQueue: DispatchQueue = .main, 
        complete: @escaping (APIResponse<T>) -> Void
    ) -> CancellableRequest? {
        // create composite behaviour to make it easy to call functions on array of behaviours
        let requestBehaviour = RequestBehaviourGroup(request: request, behaviours: self.behaviours + behaviours)

        // create the url request from the request
        var urlRequest: URLRequest
        do {
            guard let safeURL = URL(string: baseURL) else {
                throw InternalError.malformedURL
            }

            urlRequest = try request.createURLRequest(baseURL: safeURL, encoder: jsonEncoder)
        } catch {
            let error = APIClientError.requestError(.encodingError(error))
            requestBehaviour.onFailure(error: error)
            let response = APIResponse<T>(request: request, result: .failure(error))
            complete(response)
            return nil
        }

        // add the default headers
        if urlRequest.allHTTPHeaderFields == nil {
            urlRequest.allHTTPHeaderFields = [:]
        }
        for (key, value) in defaultHeaders {
            urlRequest.allHTTPHeaderFields?[key] = value
        }

        urlRequest = requestBehaviour.modifyRequest(urlRequest)

        let cancellableRequest = CancellableRequest(request: request.asAny())

        requestBehaviour.validate(urlRequest) { result in
            switch result {
            case .success(let urlRequest):
                self.makeNetworkRequest(
                    request: request, 
                    urlRequest: urlRequest, 
                    cancellableRequest: cancellableRequest, 
                    requestBehaviour: requestBehaviour,
                    requestInterceptor: interceptor,
                    completionQueue: completionQueue, 
                    complete: complete
                )
            case .failure(let error):
                let error = APIClientError.requestError(.validationError(error))
                let response = APIResponse<T>(request: request, result: .failure(error), urlRequest: urlRequest)
                requestBehaviour.onFailure(error: error)
                complete(response)
            }
        }
        return cancellableRequest
    }

    private func makeNetworkRequest<T>(
        request: APIRequest<T>,
        urlRequest: URLRequest,
        cancellableRequest: CancellableRequest,
        requestBehaviour: RequestBehaviourGroup,
        requestInterceptor: RequestInterceptor?,
        completionQueue: DispatchQueue,
        complete: @escaping (APIResponse<T>) -> Void)
    {
        requestBehaviour.beforeSend()

        let networkRequest: DataRequest
        if request.service.isUpload {
            networkRequest = session.upload(
                multipartFormData: { multipartFormData in
                    for (name, value) in request.formParameters {
                        if let file = value as? UploadFile {
                            switch file.type {
                            case let .url(url):
                                if let fileName = file.fileName, let mimeType = file.mimeType {
                                    multipartFormData.append(url, withName: name, fileName: fileName, mimeType: mimeType)
                                } else {
                                    multipartFormData.append(url, withName: name)
                                }
                            case let .data(data):
                                if let fileName = file.fileName, let mimeType = file.mimeType {
                                    multipartFormData.append(data, withName: name, fileName: fileName, mimeType: mimeType)
                                } else {
                                    multipartFormData.append(data, withName: name)
                                }
                            }
                        } else if let url = value as? URL {
                            multipartFormData.append(url, withName: name)
                        } else if let data = value as? Data {
                            multipartFormData.append(data, withName: name)
                        } else if let string = value as? String {
                            multipartFormData.append(Data(string.utf8), withName: name)
                        }
                    }
                },
                with: urlRequest
            )

        } else {
            networkRequest = session
                .request(urlRequest, interceptor: requestInterceptor)
        }

        var task: URLSessionTask?
        networkRequest
            .onURLSessionTaskCreation { task = $0 }
            .validate(statusCode: self.acceptableStatusCodes)
            .responseData(
                queue: decodingQueue,
                emptyResponseCodes: self.emptyResponseCodes
            ) { dataResponse in
                self.handleResponse(
                    urlSessionTask: task,
                    request: request,
                    requestBehaviour: requestBehaviour,
                    dataResponse: dataResponse,
                    completionQueue: completionQueue,
                    complete: complete
                )
            }

        cancellableRequest.networkRequest = networkRequest
    }

     private func handleResponse<T>(
        urlSessionTask: URLSessionTask?,
        request: APIRequest<T>, 
        requestBehaviour: RequestBehaviourGroup, 
        dataResponse: AFDataResponse<Data>, 
        completionQueue: DispatchQueue, 
        complete: @escaping (APIResponse<T>) -> Void) 
     {
        var result: APIResult<T>

        switch dataResponse.result {
        case .success(let value):

            guard let statusCode = dataResponse.response?.statusCode else {
                let apiError = APIClientError.responseError(.emptyResponse)
                result = .failure(apiError)
                requestBehaviour.onFailure(error: apiError)
                break
            }

            do {
                let decoded = try T(statusCode: statusCode, data: value, decoder: jsonDecoder)
                result = .success(decoded)
                if decoded.successful {
                    requestBehaviour.onSuccess(result: decoded.response as Any)
                    if let urlSessionTask = urlSessionTask {
                        requestBehaviour.onDecoding(urlSessionTask: urlSessionTask, error: nil)
                    }
                }
            } catch let error {
                let apiError: APIClientError
                if let error = error as? DecodingError {
                    apiError = .responseError(.decodingError(error), statusCode: statusCode, data: value)
                    if let urlSessionTask = urlSessionTask {
                        requestBehaviour.onDecoding(urlSessionTask: urlSessionTask, error: error)
                    }
                } else if let error = error as? APIClientError {
                    apiError = error
                } else {
                    apiError = .responseError(.networkError(error), statusCode: dataResponse.response?.statusCode, data: value)
                }

                result = .failure(apiError)
                requestBehaviour.onFailure(error: apiError)
            }

        case .failure(let error):
            let apiError: APIClientError

            if let statusCode = dataResponse.response?.statusCode {
                if case let .responseValidationFailed(.unacceptableStatusCode(code)) = error {
                    apiError = .responseError(.unexpectedStatusCode, statusCode: code, data: dataResponse.data)
                } else {
                    apiError = .responseError(.networkError(error), statusCode: statusCode, data: dataResponse.data)
                }
            } else {
                apiError = .responseError(.networkError(error), data: dataResponse.data)
            }
            result = .failure(apiError)
            requestBehaviour.onFailure(error: apiError)
        }
        let response = APIResponse<T>(
            request: request,
            result: result,
            urlRequest: dataResponse.request,
            urlResponse: dataResponse.response,
            data: dataResponse.data,
            metrics: dataResponse.metrics
        )
        requestBehaviour.onResponse(response: response.asAny())

        completionQueue.async {
            complete(response)
        }
    }
}

private extension APIClient {
    enum InternalError: Error {
        case malformedURL
        case emptyResponse
    }
}

public class CancellableRequest {
    /// The request used to make the actual network request
    public let request: AnyRequest

    init(request: AnyRequest) {
        self.request = request
    }

    var networkRequest: Request?

    /// cancels the request
    public func cancel() {
        networkRequest?.cancel()
    }
}

// Helper extension for sending requests
extension APIRequest {

    /// makes a request using the default APIClient. Change your baseURL in APIClient.default.baseURL
    public func makeRequest(complete: @escaping (APIResponse<ResponseType>) -> Void) {
        APIClient.default.makeRequest(self, complete: complete)
    }
}

// Create URLRequest
extension APIRequest {

    public func createURLRequest(baseURL: URL, encoder: RequestEncoder = JSONEncoder()) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = service.method
        urlRequest.allHTTPHeaderFields = headers

        // filter out parameters with empty string value
        var queryParams: [String: Any] = [:]
        for (key, value) in queryParameters {
            if !String(describing: value).isEmpty {
                queryParams[key] = value
            }
        }

        if !queryParams.isEmpty {
            urlRequest = try URLEncoding.queryString.encode(urlRequest, with: queryParams)
        }

        var formParams: [String: Any] = [:]
        for (key, value) in formParameters {
            if !String(describing: value).isEmpty {
                formParams[key] = value
            }
        }

        if !formParams.isEmpty {
            urlRequest = try URLEncoding.httpBody.encode(urlRequest, with: formParams)
        }

        if let encodeBody = encodeBody {
            urlRequest.httpBody = try encodeBody(encoder)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }
}
