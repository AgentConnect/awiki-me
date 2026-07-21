#ifndef RUNNER_SCOPE_SECRET_STORE_H_
#define RUNNER_SCOPE_SECRET_STORE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>

#include <memory>

class ScopeSecretStore {
 public:
  ScopeSecretStore() = default;
  ~ScopeSecretStore() = default;

  ScopeSecretStore(const ScopeSecretStore&) = delete;
  ScopeSecretStore& operator=(const ScopeSecretStore&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // RUNNER_SCOPE_SECRET_STORE_H_
