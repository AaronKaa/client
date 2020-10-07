//
// Copyright 2020 Iskandar Abudiab (iabudiab.dev)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import AsyncHTTPClient
import Foundation
import Logging
import NIO
import NIOHTTP1
import NIOSSL
import SwiftkubeModel

public enum KubernetesClientAuthentication {
	case basicAuth(username: String, password: String)
	case bearer(token: String)
	case x509(clientCertificate: NIOSSLCertificate, clientKey: NIOSSLPrivateKey)

	internal func authorizationHeader() -> String? {
		switch self {
		case let .basicAuth(username: username, password: password):
			return HTTPClient.Authorization.basic(username: username, password: password).headerValue
		case let .bearer(token: token):
			return HTTPClient.Authorization.bearer(tokens: token).headerValue
		default:
			return nil
		}
	}
}

public enum SwiftkubeAPIError: Error {
	case invalidURL
	case badRequest(String)
	case emptyResponse
	case decodingError(String)
	case requestError(meta.v1.Status)
}

public class KubernetesClient {

	internal static let loggingDisabled = Logger(label: "SKC-do-not-log", factory: { _ in SwiftLogNoOpLogHandler() })

	public let config: KubernetesClientConfig
	private let httpClient: HTTPClient
	
	public convenience init?(provider: HTTPClient.EventLoopGroupProvider = .createNew) {
		guard
			let config = (try? LocalFileConfigLoader().load()) ?? (try? ServiceAccountConfigLoader().load())
		else {
			return nil
		}

		self.init(config: config, provider: provider)
	}

	public init(config: KubernetesClientConfig, provider: HTTPClient.EventLoopGroupProvider = .createNew) {
		self.config = config

		var tlsConfiguration = TLSConfiguration.forClient(
			minimumTLSVersion: .tlsv12,
			certificateVerification: .fullVerification
		)

		tlsConfiguration.trustRoots = self.config.trustRoots

		if case let KubernetesClientAuthentication.x509(clientCertificate, clientKey) = self.config.authentication {
			tlsConfiguration.certificateChain = [.certificate(clientCertificate)]
			tlsConfiguration.privateKey = NIOSSLPrivateKeySource.privateKey(clientKey)
		}

		self.httpClient = HTTPClient(
			eventLoopGroupProvider: provider,
			configuration: HTTPClient.Configuration(
				tlsConfiguration: tlsConfiguration,
				redirectConfiguration: .follow(max: 10, allowCycles: false),
				timeout: .init(connect: .seconds(1))
			)
		)
	}

	public lazy var clusterRole = ClusterScopedGenericKubernetesClient<rbac.v1.ClusterRoleList>(httpClient: self.httpClient, config: self.config)
	public lazy var clusterRoleBindings = ClusterScopedGenericKubernetesClient<rbac.v1.ClusterRoleBindingList>(httpClient: self.httpClient, config: self.config)
	public lazy var configMaps = NamespacedGenericKubernetesClient<core.v1.ConfigMapList>(httpClient: self.httpClient, config: self.config)
	public lazy var daemonSets = ClusterScopedGenericKubernetesClient<apps.v1.DaemonSetList>(httpClient: self.httpClient, config: self.config)
	public lazy var deployments = NamespacedGenericKubernetesClient<apps.v1.DeploymentList>(httpClient: self.httpClient, config: self.config)
	public lazy var ingresses = NamespacedGenericKubernetesClient<networking.v1beta1.IngressList>(httpClient: self.httpClient, config: self.config)
	public lazy var namespaces = ClusterScopedGenericKubernetesClient<core.v1.NamespaceList>(httpClient: self.httpClient, config: self.config)
	public lazy var nodes = ClusterScopedGenericKubernetesClient<core.v1.NodeList>(httpClient: self.httpClient, config: self.config)
	public lazy var pods = NamespacedGenericKubernetesClient<core.v1.PodList>(httpClient: self.httpClient, config: self.config)
	public lazy var roles = NamespacedGenericKubernetesClient<rbac.v1.RoleList>(httpClient: self.httpClient, config: self.config)
	public lazy var roleBindings = NamespacedGenericKubernetesClient<rbac.v1.RoleBindingList>(httpClient: self.httpClient, config: self.config)
	public lazy var secrets = NamespacedGenericKubernetesClient<core.v1.SecretList>(httpClient: self.httpClient, config: self.config)
	public lazy var services = NamespacedGenericKubernetesClient<core.v1.ServiceList>(httpClient: self.httpClient, config: self.config)

	public func `for`<R: KubernetesResourceList>(_ type: R.Type) -> GenericKubernetesClient<R> where R.Item: KubernetesAPIResource {
		return GenericKubernetesClient<R>(httpClient: self.httpClient, config: self.config)
	}

	deinit {
		try? httpClient.syncShutdown()
	}
}
