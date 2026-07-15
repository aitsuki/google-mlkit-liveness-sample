# Google MLKit Liveness Sample

关于活体检测的详细描述可以看这篇文章：https://aitsuki.com/blog/liveness-detection-with-google-ml-kit/

## 已知问题：AGP 9 + R8 导致 ML Kit 组件注册失败

### 现象

使用 AGP 9 构建开启 R8 压缩的 Android release 包时，应用启动日志可能出现：

```text
W/ComponentDiscovery: Invalid component registrar.
Caused by: java.lang.NoSuchMethodException:
com.google.mlkit.common.internal.CommonComponentRegistrar.<init> []
```

`FaceRegistrar` 和 `VisionCommonRegistrar` 也可能出现相同异常。组件发现流程会捕获异常并
继续启动，所以问题可能直到创建或执行人脸检测器时才表现为报错、检测无法继续或进程崩溃：

```text
E/AndroidRuntime: java.lang.NullPointerException: 
Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()' on a null object reference
```


### 原因

ML Kit 间接依赖的 `firebase-components:16.1.0` 只保留
`ComponentRegistrar` 实现类，没有显式保留反射所需的无参构造器：

```proguard
-keep class * implements com.google.firebase.components.ComponentRegistrar
```

AGP 8.x 和 9.x 都默认启用 R8 full mode，但 keep rule 的兼容行为不同：

- AGP 8.x 的 `android.r8.strictFullModeForKeepRules` 默认为 `false`，
  `-keep class A` 仍会兼容性地保留 `A()`。
- AGP 9.0 将该选项默认为 `true`，`-keep class A` 不再隐式保留 `A()`，
  必须明确写出 `<init>()`。

因此旧规则在 AGP 8.x 下可以工作，升级到 AGP 9 后会暴露构造器缺失。ML Kit 的自动初始化
链路如下：

```text
Android 启动应用
  -> MlKitInitProvider.onCreate()
  -> MlKitContext.initialize(context)
  -> ComponentDiscovery 读取 Manifest 中的 registrar
  -> 反射创建 CommonComponentRegistrar
  -> ComponentRuntime 调用 registrar.getComponents()
```

构造器缺失会使流程停在反射创建阶段，`getComponents()` 不会执行，
`SharedPrefManager` 等依赖也不会注册。

### 修复

在应用的 R8 规则中显式保留 registrar 的无参构造器：

```proguard
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    void <init>();
}
-keep,allowshrinking interface com.google.firebase.components.ComponentRegistrar
```

本仓库的两个 Android 应用均已加载该规则：

- [原生 Android 规则](android/app/proguard-rules.pro)
- [Flutter Android 规则](flutter/android/app/proguard-rules.pro)

该规则来自 Firebase 官方修复，并在 `firebase-components:18.0.1` 发布。应用层补充规则可以
避免强制覆盖 ML Kit 的传递依赖版本。

### 参考资料

- [AGP 9.0 官方发布说明：strictFullModeForKeepRules 默认值由 false 改为 true](https://developer.android.com/build/releases/agp-9-0-0-release-notes)
- [R8 严格 keep rule 语义变更](https://r8.googlesource.com/r8/+/06e32a8d0d2e7e28bc4e597e4ce96e2e0c229d08)
- [Firebase 官方 PR #6044](https://github.com/firebase/firebase-android-sdk/pull/6044)
- [Firebase 官方修复提交](https://github.com/firebase/firebase-android-sdk/commit/60d67c74814cae32aa41e2ed6e712195dd1d0f19)
- [firebase-components 18.0.1 更新记录](https://github.com/firebase/firebase-android-sdk/blob/main/firebase-components/CHANGELOG.md#1801)
