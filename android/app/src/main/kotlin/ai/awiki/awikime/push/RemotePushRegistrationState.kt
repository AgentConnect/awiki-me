package ai.awiki.awikime.push

internal enum class RemotePushRegistrationAction {
    START,
    JOIN_IN_FLIGHT,
}

internal class RemotePushRegistrationState {
    private var inFlight = false

    fun beginInitialization(): RemotePushRegistrationAction {
        if (inFlight) {
            return RemotePushRegistrationAction.JOIN_IN_FLIGHT
        }
        inFlight = true
        return RemotePushRegistrationAction.START
    }

    fun completeSuccess() {
        inFlight = false
    }

    fun completeFailure() {
        inFlight = false
    }
}
