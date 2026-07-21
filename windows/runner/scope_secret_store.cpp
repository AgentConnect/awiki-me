#include "scope_secret_store.h"

#include <wincred.h>
#include <wincrypt.h>
#include <windows.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/base.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <iomanip>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using JsonObject = winrt::Windows::Data::Json::JsonObject;
using JsonValueType = winrt::Windows::Data::Json::JsonValueType;

constexpr DWORD kMutexWaitMilliseconds = 10000;
constexpr double kMaxSafeJsonInteger = 9007199254740991.0;

struct ScopeSecretRequest {
  std::string service;
  std::string account;
  std::string value;
  int64_t expected_revision = 0;

  ~ScopeSecretRequest() {
    if (!value.empty()) {
      ::SecureZeroMemory(value.data(), value.size());
    }
  }
};

struct CredentialReadResult {
  bool found = false;
  DWORD error = ERROR_SUCCESS;
  std::string value;

  ~CredentialReadResult() {
    if (!value.empty()) {
      ::SecureZeroMemory(value.data(), value.size());
    }
  }
};

class TargetMutex {
 public:
  explicit TargetMutex(const std::wstring& target_name) {
    uint64_t hash = 1469598103934665603ULL;
    for (const wchar_t unit : target_name) {
      hash ^= static_cast<uint16_t>(unit);
      hash *= 1099511628211ULL;
    }
    std::wostringstream name;
    name << L"Local\\AWikiMe.ScopeSecret." << std::hex << std::setw(16)
         << std::setfill(L'0') << hash;
    handle_ = ::CreateMutexW(nullptr, FALSE, name.str().c_str());
    if (handle_ == nullptr) {
      error_ = ::GetLastError();
      return;
    }
    const DWORD wait = ::WaitForSingleObject(handle_, kMutexWaitMilliseconds);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      locked_ = true;
      return;
    }
    error_ = wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : ::GetLastError();
  }

  ~TargetMutex() {
    if (locked_) {
      ::ReleaseMutex(handle_);
    }
    if (handle_ != nullptr) {
      ::CloseHandle(handle_);
    }
  }

  bool locked() const { return locked_; }
  DWORD error() const { return error_; }

 private:
  HANDLE handle_ = nullptr;
  bool locked_ = false;
  DWORD error_ = ERROR_SUCCESS;
};

const EncodableMap* ArgumentsMap(const EncodableValue* arguments) {
  return arguments == nullptr ? nullptr : std::get_if<EncodableMap>(arguments);
}

const EncodableValue* MapValue(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(std::string(key)));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::string> StringValue(const EncodableMap& map,
                                       const char* key) {
  const EncodableValue* value = MapValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  const auto* string_value = std::get_if<std::string>(value);
  return string_value == nullptr ? std::nullopt
                                 : std::optional<std::string>(*string_value);
}

std::optional<int64_t> IntegerValue(const EncodableMap& map, const char* key) {
  const EncodableValue* value = MapValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return *int64_value;
  }
  return std::nullopt;
}

bool IsLowerHex(char value) {
  return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
}

bool IsCanonicalUuidV4(const std::string& value) {
  if (value.size() != 36 || value[8] != '-' || value[13] != '-' ||
      value[18] != '-' || value[23] != '-' || value[14] != '4' ||
      (value[19] != '8' && value[19] != '9' && value[19] != 'a' &&
       value[19] != 'b')) {
    return false;
  }
  for (size_t index = 0; index < value.size(); ++index) {
    if (index == 8 || index == 13 || index == 18 || index == 23) {
      continue;
    }
    if (!IsLowerHex(value[index])) {
      return false;
    }
  }
  return true;
}

bool IsAllowedService(const std::string& service) {
#if defined(AWIKI_RELEASE_SCOPE)
  return service == "ai.awiki.awikime.scope-secrets";
#else
  return service == "ai.awiki.awikime.dev.scope-secrets";
#endif
}

bool IsCanonicalAccount(const std::string& account) {
  constexpr char kPrefix[] = "scope/";
  return account.rfind(kPrefix, 0) == 0 &&
         IsCanonicalUuidV4(account.substr(sizeof(kPrefix) - 1));
}

std::wstring TargetName(const ScopeSecretRequest& request) {
  return Utf16FromUtf8(request.service + "/" + request.account);
}

bool HasExactKeys(const JsonObject& object,
                  std::initializer_list<const wchar_t*> keys) {
  if (static_cast<size_t>(object.Size()) != keys.size()) {
    return false;
  }
  return std::all_of(keys.begin(), keys.end(), [&object](const wchar_t* key) {
    return object.HasKey(key);
  });
}

std::optional<int64_t> StrictJsonInteger(
    const winrt::Windows::Data::Json::IJsonValue& value) {
  if (value.ValueType() != JsonValueType::Number) {
    return std::nullopt;
  }
  const double number = value.GetNumber();
  if (!std::isfinite(number) || std::floor(number) != number || number < 0 ||
      number > kMaxSafeJsonInteger) {
    return std::nullopt;
  }
  return static_cast<int64_t>(number);
}

bool IsCanonicalBase64Key(const std::string& encoded) {
  const std::wstring wide = Utf16FromUtf8(encoded);
  if (wide.empty()) {
    return false;
  }
  DWORD byte_count = 0;
  if (!::CryptStringToBinaryW(wide.c_str(), static_cast<DWORD>(wide.size()),
                              CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT,
                              nullptr, &byte_count, nullptr, nullptr) ||
      byte_count != 32) {
    return false;
  }
  std::vector<BYTE> bytes(byte_count);
  if (!::CryptStringToBinaryW(wide.c_str(), static_cast<DWORD>(wide.size()),
                              CRYPT_STRING_BASE64 | CRYPT_STRING_STRICT,
                              bytes.data(), &byte_count, nullptr, nullptr)) {
    return false;
  }
  DWORD encoded_count = 0;
  if (!::CryptBinaryToStringW(bytes.data(), byte_count,
                              CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                              nullptr, &encoded_count) ||
      encoded_count == 0) {
    ::SecureZeroMemory(bytes.data(), bytes.size());
    return false;
  }
  std::wstring canonical(encoded_count, L'\0');
  const bool encoded_ok = ::CryptBinaryToStringW(
      bytes.data(), byte_count, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
      canonical.data(), &encoded_count);
  ::SecureZeroMemory(bytes.data(), bytes.size());
  if (!encoded_ok) {
    return false;
  }
  if (!canonical.empty() && canonical.back() == L'\0') {
    canonical.pop_back();
  }
  return canonical == wide;
}

std::optional<int64_t> ValidateEnvelope(const std::string& value,
                                        const std::string& account,
                                        bool require_scope_match) {
  try {
    const JsonObject envelope = JsonObject::Parse(winrt::to_hstring(value));
    if (!HasExactKeys(envelope, {L"schema_version", L"scope_id", L"revision",
                                 L"active_secrets"})) {
      return std::nullopt;
    }
    const auto schema =
        StrictJsonInteger(envelope.GetNamedValue(L"schema_version"));
    const auto revision =
        StrictJsonInteger(envelope.GetNamedValue(L"revision"));
    if (!schema.has_value() || *schema != 1 || !revision.has_value() ||
        *revision < 1) {
      return std::nullopt;
    }
    const std::string scope_id =
        winrt::to_string(envelope.GetNamedString(L"scope_id"));
    if (!IsCanonicalUuidV4(scope_id) ||
        (require_scope_match && account != "scope/" + scope_id)) {
      return std::nullopt;
    }
    const JsonObject active = envelope.GetNamedObject(L"active_secrets");
    if (!HasExactKeys(active, {L"identity_vault_root"})) {
      return std::nullopt;
    }
    const JsonObject root = active.GetNamedObject(L"identity_vault_root");
    if (!HasExactKeys(
            root, {L"key_id", L"key_version", L"algorithm", L"material_b64"})) {
      return std::nullopt;
    }
    const auto key_version =
        StrictJsonInteger(root.GetNamedValue(L"key_version"));
    const std::string key_id = winrt::to_string(root.GetNamedString(L"key_id"));
    const std::string algorithm =
        winrt::to_string(root.GetNamedString(L"algorithm"));
    const std::string material =
        winrt::to_string(root.GetNamedString(L"material_b64"));
    if (!key_version.has_value() || *key_version != 1 ||
        !IsCanonicalUuidV4(key_id) || algorithm != "raw-256" ||
        !IsCanonicalBase64Key(material)) {
      return std::nullopt;
    }
    return revision;
  } catch (const winrt::hresult_error&) {
    return std::nullopt;
  }
}

bool IsValidUtf8(const std::string& value) {
  if (value.empty()) {
    return false;
  }
  return !Utf16FromUtf8(value).empty();
}

ScopeSecretRequest* ParseRequest(
    const flutter::MethodCall<EncodableValue>& call,
    bool require_value,
    bool require_revision,
    ScopeSecretRequest* output) {
  const EncodableMap* arguments = ArgumentsMap(call.arguments());
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto service = StringValue(*arguments, "service");
  const auto account = StringValue(*arguments, "account");
  if (!service.has_value() || !account.has_value() ||
      !IsAllowedService(*service) || !IsCanonicalAccount(*account)) {
    return nullptr;
  }
  output->service = *service;
  output->account = *account;
  if (require_value) {
    const auto value = StringValue(*arguments, "value");
    if (!value.has_value() || value->empty()) {
      return nullptr;
    }
    output->value = *value;
  }
  if (require_revision) {
    const auto revision = IntegerValue(*arguments, "expected_revision");
    if (!revision.has_value() || *revision < 1) {
      return nullptr;
    }
    output->expected_revision = *revision;
  }
  return output;
}

CredentialReadResult ReadCredential(const std::wstring& target_name,
                                    const std::wstring& account) {
  PCREDENTIALW credential = nullptr;
  if (!::CredReadW(target_name.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
    const DWORD error = ::GetLastError();
    return CredentialReadResult{false, error, {}};
  }
  CredentialReadResult response;
  response.found = true;
  const bool metadata_is_valid =
      credential->Type == CRED_TYPE_GENERIC &&
      credential->Persist == CRED_PERSIST_LOCAL_MACHINE &&
      credential->TargetName != nullptr &&
      target_name == credential->TargetName &&
      credential->UserName != nullptr && account == credential->UserName;
  if (!metadata_is_valid || credential->CredentialBlob == nullptr ||
      credential->CredentialBlobSize == 0 ||
      credential->CredentialBlobSize >
          static_cast<DWORD>(CRED_MAX_CREDENTIAL_BLOB_SIZE)) {
    response.error = ERROR_INVALID_DATA;
  } else {
    response.value.assign(
        reinterpret_cast<const char*>(credential->CredentialBlob),
        credential->CredentialBlobSize);
  }
  if (credential->CredentialBlob != nullptr &&
      credential->CredentialBlobSize > 0) {
    ::SecureZeroMemory(credential->CredentialBlob,
                       credential->CredentialBlobSize);
  }
  ::CredFree(credential);
  return response;
}

DWORD WriteCredential(const ScopeSecretRequest& request,
                      const std::wstring& target_name) {
  if (request.value.empty() ||
      request.value.size() >
          static_cast<size_t>(CRED_MAX_CREDENTIAL_BLOB_SIZE)) {
    return ERROR_INVALID_DATA;
  }
  const std::wstring account = Utf16FromUtf8(request.account);
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<LPWSTR>(target_name.c_str());
  credential.CredentialBlobSize = static_cast<DWORD>(request.value.size());
  credential.CredentialBlob =
      reinterpret_cast<LPBYTE>(const_cast<char*>(request.value.data()));
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = const_cast<LPWSTR>(account.c_str());
  if (!::CredWriteW(&credential, 0)) {
    return ::GetLastError();
  }
  return ERROR_SUCCESS;
}

std::string StableErrorFor(DWORD error) {
  switch (error) {
    case ERROR_ACCESS_DENIED:
    case ERROR_CANCELLED:
    case ERROR_PRIVILEGE_NOT_HELD:
      return "scope_secret_access_denied";
    case ERROR_NO_SUCH_LOGON_SESSION:
    case ERROR_TIMEOUT:
    case ERROR_SERVICE_NOT_ACTIVE:
      return "scope_secret_provider_unavailable";
    case ERROR_INVALID_DATA:
    case ERROR_BAD_FORMAT:
      return "scope_secret_corrupt";
    default:
      return "scope_secret_operation_failed";
  }
}

void ReturnError(std::unique_ptr<flutter::MethodResult<EncodableValue>>& result,
                 const std::string& code,
                 DWORD native_error) {
  result->Error(code, "Scope secret operation failed",
                EncodableValue(static_cast<int64_t>(native_error)));
}

void ReturnNativeError(
    std::unique_ptr<flutter::MethodResult<EncodableValue>>& result,
    DWORD native_error) {
  ReturnError(result, StableErrorFor(native_error), native_error);
}

}  // namespace

void ScopeSecretStore::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const bool is_read = method == "readScopeSecret";
  const bool is_create = method == "createScopeSecretExclusive";
  const bool is_replace = method == "compareAndReplaceScopeSecret";
  const bool is_delete = method == "deleteScopeSecret";
  if (!is_read && !is_create && !is_replace && !is_delete) {
    result->NotImplemented();
    return;
  }

  ScopeSecretRequest request;
  if (ParseRequest(call, is_create || is_replace, is_replace, &request) ==
      nullptr) {
    ReturnError(result, "scope_secret_bad_request", ERROR_INVALID_PARAMETER);
    return;
  }
  const std::wstring target_name = TargetName(request);
  const std::wstring account = Utf16FromUtf8(request.account);
  if (target_name.empty() || account.empty()) {
    ReturnError(result, "scope_secret_bad_request", ERROR_INVALID_PARAMETER);
    return;
  }

  if (is_read) {
    CredentialReadResult current = ReadCredential(target_name, account);
    if (!current.found && current.error == ERROR_NOT_FOUND) {
      result->Success();
      return;
    }
    if (current.error != ERROR_SUCCESS) {
      ReturnNativeError(result, current.error);
      return;
    }
    if (!IsValidUtf8(current.value)) {
      ::SecureZeroMemory(current.value.data(), current.value.size());
      ReturnError(result, "scope_secret_corrupt", ERROR_INVALID_DATA);
      return;
    }
    const EncodableValue returned_value(current.value);
    result->Success(returned_value);
    ::SecureZeroMemory(current.value.data(), current.value.size());
    return;
  }

  TargetMutex mutex(target_name);
  if (!mutex.locked()) {
    ReturnNativeError(result, mutex.error());
    return;
  }

  if (is_create) {
    const auto revision =
        ValidateEnvelope(request.value, request.account, true);
    if (!revision.has_value() || *revision != 1) {
      ReturnError(result, "scope_secret_corrupt", ERROR_INVALID_DATA);
      return;
    }
    CredentialReadResult current = ReadCredential(target_name, account);
    if (current.found) {
      if (!current.value.empty()) {
        ::SecureZeroMemory(current.value.data(), current.value.size());
      }
      ReturnError(result, "scope_secret_already_exists", ERROR_ALREADY_EXISTS);
      return;
    }
    if (current.error != ERROR_NOT_FOUND) {
      ReturnNativeError(result, current.error);
      return;
    }
    const DWORD write_error = WriteCredential(request, target_name);
    if (write_error != ERROR_SUCCESS) {
      ReturnNativeError(result, write_error);
      return;
    }
    result->Success();
    return;
  }

  if (is_replace) {
    CredentialReadResult current = ReadCredential(target_name, account);
    if (!current.found && current.error == ERROR_NOT_FOUND) {
      ReturnError(result, "scope_secret_revision_conflict", ERROR_NOT_FOUND);
      return;
    }
    if (current.error != ERROR_SUCCESS) {
      ReturnNativeError(result, current.error);
      return;
    }
    const auto current_revision =
        ValidateEnvelope(current.value, request.account, true);
    ::SecureZeroMemory(current.value.data(), current.value.size());
    const auto replacement_revision =
        ValidateEnvelope(request.value, request.account, true);
    if (!current_revision.has_value() || !replacement_revision.has_value()) {
      ReturnError(result, "scope_secret_corrupt", ERROR_INVALID_DATA);
      return;
    }
    if (*current_revision != request.expected_revision ||
        request.expected_revision == INT64_MAX ||
        *replacement_revision != request.expected_revision + 1) {
      ReturnError(result, "scope_secret_revision_conflict",
                  ERROR_REVISION_MISMATCH);
      return;
    }
    const DWORD write_error = WriteCredential(request, target_name);
    if (write_error != ERROR_SUCCESS) {
      ReturnNativeError(result, write_error);
      return;
    }
    result->Success();
    return;
  }

  if (!::CredDeleteW(target_name.c_str(), CRED_TYPE_GENERIC, 0)) {
    const DWORD error = ::GetLastError();
    if (error != ERROR_NOT_FOUND) {
      ReturnNativeError(result, error);
      return;
    }
  }
  result->Success();
}
