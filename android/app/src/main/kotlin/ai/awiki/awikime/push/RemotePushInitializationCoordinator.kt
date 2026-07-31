package ai.awiki.awikime.push

internal interface RemotePushInitializationCallback {
    fun onSuccess(response: String?)

    fun onFailure(errorCode: String?, errorMessage: String?)
}

internal interface RemotePushInitializationClient {
    fun readyDeviceId(): String?

    fun register(callback: RemotePushInitializationCallback)

    fun turnOnPushChannel(callback: RemotePushInitializationCallback)
}

internal sealed interface RemotePushInitializationResult {
    data class Success(
        val registrationChanged: Boolean,
    ) : RemotePushInitializationResult

    data class Failure(
        val errorCode: String,
        val errorMessage: String?,
    ) : RemotePushInitializationResult
}

internal class RemotePushInitializationCoordinator(
    private val client: RemotePushInitializationClient,
) {
    private val lock = Any()
    private val state = RemotePushRegistrationState()
    private val pendingCompletions = mutableListOf<(RemotePushInitializationResult) -> Unit>()

    fun initialize(completion: (RemotePushInitializationResult) -> Unit) {
        val action = synchronized(lock) {
            pendingCompletions.add(completion)
            state.beginInitialization()
        }
        if (action != RemotePushRegistrationAction.START) return

        runCatching {
            register(registrationChanged = client.readyDeviceId() == null)
        }.onFailure(::completeNativeFailure)
    }

    private fun register(registrationChanged: Boolean) {
        client.register(
            object : RemotePushInitializationCallback {
                override fun onSuccess(response: String?) {
                    turnOnPushChannel(registrationChanged = registrationChanged)
                }

                override fun onFailure(errorCode: String?, errorMessage: String?) {
                    if (errorCode == "PUSH_20110" && client.readyDeviceId() != null) {
                        turnOnPushChannel(registrationChanged = false)
                        return
                    }
                    completeFailure(errorCode, errorMessage)
                }
            },
        )
    }

    private fun turnOnPushChannel(registrationChanged: Boolean) {
        runCatching {
            client.turnOnPushChannel(
                object : RemotePushInitializationCallback {
                    override fun onSuccess(response: String?) {
                        complete(
                            RemotePushInitializationResult.Success(
                                registrationChanged = registrationChanged,
                            ),
                        )
                    }

                    override fun onFailure(errorCode: String?, errorMessage: String?) {
                        completeFailure(errorCode, errorMessage)
                    }
                },
            )
        }.onFailure(::completeNativeFailure)
    }

    private fun completeNativeFailure(error: Throwable) {
        completeFailure("native_exception", error.javaClass.simpleName)
    }

    private fun completeFailure(errorCode: String?, errorMessage: String?) {
        complete(
            RemotePushInitializationResult.Failure(
                errorCode = errorCode ?: "initialization_failed",
                errorMessage = errorMessage,
            ),
        )
    }

    private fun complete(result: RemotePushInitializationResult) {
        val completions = synchronized(lock) {
            when (result) {
                is RemotePushInitializationResult.Success -> state.completeSuccess()
                is RemotePushInitializationResult.Failure -> state.completeFailure()
            }
            pendingCompletions.toList().also { pendingCompletions.clear() }
        }
        completions.forEach { it(result) }
    }
}
