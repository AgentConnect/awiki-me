package ai.awiki.awikime.push

internal enum class RemotePushRegistrationAction {
    START,
    JOIN_IN_FLIGHT,
    RETURN_SUCCESS,
}

internal class RemotePushRegistrationState {
    private var inFlight = false
    private var succeeded = false

    fun beginInitialization(): RemotePushRegistrationAction {
        if (succeeded) {
            return RemotePushRegistrationAction.RETURN_SUCCESS
        }
        if (inFlight) {
            return RemotePushRegistrationAction.JOIN_IN_FLIGHT
        }
        inFlight = true
        return RemotePushRegistrationAction.START
    }

    fun completeSuccess() {
        inFlight = false
        succeeded = true
    }

    fun completeFailure() {
        inFlight = false
    }
}
