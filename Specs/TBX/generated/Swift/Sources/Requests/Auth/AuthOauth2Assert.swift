//
// Generated by SwagGen
// https://github.com/yonaskolb/SwagGen
//

import Foundation

extension TBX.Auth {

    /** Return Url from OAuth2.0 login */
    public enum AuthOauth2Assert {

        public static let service = APIService<Response>(id: "auth.oauth2Assert", tag: "auth", method: "GET", path: "/auth/oauth2/assert", hasBody: false)

        public final class Request: APIRequest<Response> {

            public struct Options {

                public var code: String?

                public var state: String?

                public init(code: String? = nil, state: String? = nil) {
                    self.code = code
                    self.state = state
                }
            }

            public var options: Options

            public init(options: Options) {
                self.options = options
                super.init(service: AuthOauth2Assert.service)
            }

            /// convenience initialiser so an Option doesn't have to be created
            public convenience init(code: String? = nil, state: String? = nil) {
                let options = Options(code: code, state: state)
                self.init(options: options)
            }

            public override var queryParameters: [String: Any] {
                var params: [String: Any] = [:]
                if let code = options.code {
                  params["code"] = code
                }
                if let state = options.state {
                  params["state"] = state
                }
                return params
            }
        }

        public enum Response: APIResponseValue, CustomStringConvertible, CustomDebugStringConvertible {
            public typealias SuccessType = [String: Any]

            /** Request was successful */
            case status200([String: Any])

            public var success: [String: Any]? {
                switch self {
                case .status200(let response): return response
                }
            }

            public var response: Any {
                switch self {
                case .status200(let response): return response
                }
            }

            public var statusCode: Int {
                switch self {
                case .status200: return 200
                }
            }

            public var successful: Bool {
                switch self {
                case .status200: return true
                }
            }

            public init(statusCode: Int, data: Data, decoder: ResponseDecoder) throws {
                switch statusCode {
                case 200: self = try .status200(decoder.decodeAny([String: Any].self, from: data))
                default: throw APIClientError.unexpectedStatusCode(statusCode: statusCode, data: data)
                }
            }

            public var description: String {
                return "\(statusCode) \(successful ? "success" : "failure")"
            }

            public var debugDescription: String {
                var string = description
                let responseString = "\(response)"
                if responseString != "()" {
                    string += "\n\(responseString)"
                }
                return string
            }
        }
    }
}
