//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import AwsCAuth

private func getCredentialsFn(_ credentialsProviderPtr: UnsafeMutablePointer<aws_credentials_provider>?, _ callbackFn: (@convention(c)(OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void)?, userData: UnsafeMutableRawPointer?) -> Int32 {

    guard let credentialsProvider = userData?.assumingMemoryBound(to: CredentialsProvider.self) else {
        return 1
    }

    var credentialCallbackData = CredentialsProviderCallbackData(allocator: credentialsProvider.pointee.allocator)
    let callbackPointer = UnsafeMutablePointer<CredentialsProviderCallbackData>.allocate(capacity: 1)
    callbackPointer.initialize(to: credentialCallbackData)
    credentialCallbackData.onCredentialsResolved = { (credentials, errorCode) in
        callbackFn?(credentials?.rawValue, errorCode, callbackPointer)
    }
    credentialsProvider.pointee.getCredentials(credentialCallbackData: credentialCallbackData)
   return 0
}

public protocol CredentialsProvider {
    var allocator: Allocator {get set}
    func getCredentials(credentialCallbackData: CredentialsProviderCallbackData)

}

class WrappedCredentialsProvider {
    var rawValue: aws_credentials_provider
    let allocator: Allocator

    init(impl: inout CredentialsProvider, allocator: Allocator, shutDownOptions: CredentialsProviderShutdownOptions? = nil) {
        var vtable = aws_credentials_provider_vtable(get_credentials: getCredentialsFn, destroy: { (credentialsProviderPtr) in
            guard let credentialsProviderPtr = credentialsProviderPtr else {
                return
            }

            aws_credentials_provider_release(credentialsProviderPtr)

        })
        let shutDownOptions = Self.setUpShutDownOptions(shutDownOptions: shutDownOptions)
        let intPointer = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        intPointer.pointee = 1
        let atomicVar = aws_atomic_var(value: UnsafeMutableRawPointer(intPointer))
        self.allocator = allocator
        self.rawValue = aws_credentials_provider(vtable: &vtable,
                                                 allocator: allocator.rawValue,
                                                 shutdown_options: shutDownOptions,
                                                 impl: &impl,
                                                 ref_count: atomicVar)

    }

    static func setUpShutDownOptions(shutDownOptions: CredentialsProviderShutdownOptions?) -> aws_credentials_provider_shutdown_options {
        let shutDownOptionsC: aws_credentials_provider_shutdown_options?
        if let shutDownOptions = shutDownOptions {

            let pointer = UnsafeMutablePointer<CredentialsProviderShutdownOptions>.allocate(capacity: 1)
            pointer.initialize(to: shutDownOptions)
            shutDownOptionsC = aws_credentials_provider_shutdown_options(shutdown_callback: { userData in
                guard let userData = userData else {
                    return
                }
                let pointer = userData.assumingMemoryBound(to: CredentialsProviderShutdownOptions.self)
                defer {pointer.deinitializeAndDeallocate()}
                pointer.pointee.shutDownCallback()

            }, shutdown_user_data: pointer)
        } else {
            shutDownOptionsC = aws_credentials_provider_shutdown_options()
        }
        return shutDownOptionsC!
    }
}
