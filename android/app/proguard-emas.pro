# EMAS Push and its network stack discover implementations through runtime
# annotations, SPI metadata, and reflection. Keep that closed-source surface
# stable in minified release builds.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod

-keep class com.alibaba.** { *; }
-keep class com.aliyun.** { *; }
-keep class com.taobao.** { *; }
-keep class anet.channel.** { *; }
-keep class anetwork.channel.** { *; }
-keep class org.android.agoo.** { *; }
-keep class org.android.spdy.** { *; }
-keep class mtopsdk.** { *; }

# Optional integrations referenced by the bundled EMAS network stack but not
# shipped by alicloud-android-push. Keep the suppression exact so a new missing
# runtime dependency still fails the release build.
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Alarm
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Counter
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor$Stat
-dontwarn com.alibaba.mtl.appmonitor.AppMonitor
-dontwarn com.alibaba.mtl.appmonitor.model.DimensionSet
-dontwarn com.alibaba.mtl.appmonitor.model.DimensionValueSet
-dontwarn com.alibaba.mtl.appmonitor.model.Measure
-dontwarn com.alibaba.mtl.appmonitor.model.MeasureSet
-dontwarn com.alibaba.mtl.appmonitor.model.MeasureValueSet
-dontwarn com.alibaba.wireless.security.open.SecurityGuardManager
-dontwarn com.alibaba.wireless.security.open.SecurityGuardParamContext
-dontwarn com.alibaba.wireless.security.open.dynamicdatastore.IDynamicDataStoreComponent
-dontwarn com.alibaba.wireless.security.open.securesignature.ISecureSignatureComponent
-dontwarn com.alibaba.wireless.security.open.staticdataencrypt.IStaticDataEncryptComponent
-dontwarn com.taobao.alivfssdk.cache.AVFSCache
-dontwarn com.taobao.alivfssdk.cache.AVFSCacheConfig
-dontwarn com.taobao.alivfssdk.cache.AVFSCacheManager
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnAllObjectRemoveCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnObjectRemoveCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache$OnObjectSetCallback
-dontwarn com.taobao.alivfssdk.cache.IAVFSCache
-dontwarn com.taobao.analysis.FlowCenter
-dontwarn com.taobao.analysis.abtest.ABTestCenter
-dontwarn com.taobao.analysis.fulltrace.FullTraceAnalysis
-dontwarn com.taobao.analysis.fulltrace.RequestInfo
-dontwarn com.taobao.analysis.scene.SceneIdentifier
-dontwarn com.taobao.orange.OrangeConfig
-dontwarn com.taobao.orange.OrangeConfigListenerV1
-dontwarn com.taobao.tlog.adapter.AdapterForTLog
-dontwarn org.android.netutil.NetUtils
