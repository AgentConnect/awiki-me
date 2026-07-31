package ai.awiki.awikime.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RemotePushInitializationCoordinatorTest {
    @Test
    fun `existing device id re-registers before turning on the push channel`() {
        val client = FakeRemotePushInitializationClient(deviceId = "existing-device")
        val coordinator = RemotePushInitializationCoordinator(client)
        val results = mutableListOf<RemotePushInitializationResult>()

        coordinator.initialize(results::add)

        assertEquals(1, client.registerCalls)
        assertEquals(0, client.turnOnPushChannelCalls)
        assertTrue(results.isEmpty())

        client.completeRegistrationSuccess()

        assertEquals(1, client.turnOnPushChannelCalls)
        assertTrue(results.isEmpty())

        client.completeTurnOnSuccess()

        assertEquals(
            listOf(RemotePushInitializationResult.Success(registrationChanged = false)),
            results,
        )
    }

    @Test
    fun `new registration turns on the push channel before succeeding`() {
        val client = FakeRemotePushInitializationClient(deviceId = null)
        val coordinator = RemotePushInitializationCoordinator(client)
        val results = mutableListOf<RemotePushInitializationResult>()

        coordinator.initialize(results::add)

        assertEquals(1, client.registerCalls)
        assertEquals(0, client.turnOnPushChannelCalls)
        assertTrue(results.isEmpty())

        client.deviceId = "new-device"
        client.completeRegistrationSuccess()

        assertEquals(1, client.turnOnPushChannelCalls)
        assertTrue(results.isEmpty())

        client.completeTurnOnSuccess()

        assertEquals(
            listOf(RemotePushInitializationResult.Success(registrationChanged = true)),
            results,
        )
    }

    @Test
    fun `later initialization rechecks an existing push channel`() {
        val client = FakeRemotePushInitializationClient(deviceId = "existing-device")
        val coordinator = RemotePushInitializationCoordinator(client)
        val results = mutableListOf<RemotePushInitializationResult>()

        coordinator.initialize(results::add)
        client.completeRegistrationSuccess()
        client.completeTurnOnSuccess()
        coordinator.initialize(results::add)

        assertEquals(2, client.registerCalls)
        assertEquals(1, client.turnOnPushChannelCalls)
        assertEquals(1, results.size)

        client.completeRegistrationSuccess()
        client.completeTurnOnSuccess()

        assertEquals(2, results.size)
    }

    @Test
    fun `channel recovery failure permits the next initialization attempt`() {
        val client = FakeRemotePushInitializationClient(deviceId = "existing-device")
        val coordinator = RemotePushInitializationCoordinator(client)
        val results = mutableListOf<RemotePushInitializationResult>()

        coordinator.initialize(results::add)
        client.completeRegistrationSuccess()
        client.completeTurnOnFailure("channel_offline", "offline")
        coordinator.initialize(results::add)

        assertEquals(2, client.registerCalls)
        assertEquals(1, client.turnOnPushChannelCalls)
        assertEquals(
            RemotePushInitializationResult.Failure("channel_offline", "offline"),
            results.single(),
        )
    }

    @Test
    fun `concurrent initialization joins one channel recovery`() {
        val client = FakeRemotePushInitializationClient(deviceId = "existing-device")
        val coordinator = RemotePushInitializationCoordinator(client)
        val results = mutableListOf<RemotePushInitializationResult>()

        coordinator.initialize(results::add)
        coordinator.initialize(results::add)

        assertEquals(1, client.registerCalls)
        assertEquals(0, client.turnOnPushChannelCalls)

        client.completeRegistrationSuccess()
        assertEquals(1, client.turnOnPushChannelCalls)

        client.completeTurnOnSuccess()

        assertEquals(2, results.size)
    }
}

private class FakeRemotePushInitializationClient(
    var deviceId: String?,
) : RemotePushInitializationClient {
    var registerCalls = 0
        private set
    var turnOnPushChannelCalls = 0
        private set
    private var registrationCallback: RemotePushInitializationCallback? = null
    private var turnOnCallback: RemotePushInitializationCallback? = null

    override fun readyDeviceId(): String? = deviceId

    override fun register(callback: RemotePushInitializationCallback) {
        registerCalls += 1
        registrationCallback = callback
    }

    override fun turnOnPushChannel(callback: RemotePushInitializationCallback) {
        turnOnPushChannelCalls += 1
        turnOnCallback = callback
    }

    fun completeRegistrationSuccess() {
        registrationCallback.also { registrationCallback = null }?.onSuccess("registered")
    }

    fun completeTurnOnSuccess() {
        turnOnCallback.also { turnOnCallback = null }?.onSuccess("on")
    }

    fun completeTurnOnFailure(code: String, message: String) {
        turnOnCallback.also { turnOnCallback = null }?.onFailure(code, message)
    }
}
