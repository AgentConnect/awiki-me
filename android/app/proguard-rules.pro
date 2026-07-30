# Alibaba NetworkSDK 3.6.0-open references an optional native ping helper that
# is not shipped by the EMAS Push 3.10.1 dependency graph.
-dontwarn org.android.netutil.PingEntry
-dontwarn org.android.netutil.PingResponse
-dontwarn org.android.netutil.PingTask
