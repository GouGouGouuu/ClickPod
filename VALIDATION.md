# Validation / 验证

Test environment: Apple Silicon, macOS 26, Swift 6.3.3, Blender 4.5.9 LTS.

- Native build targets arm64/macOS 14. Ad-hoc signature and bundle metadata checks pass.
- Blender exports 12 meshes and 17,216 triangles; vertex, normal and index consistency checks pass.
- Navigation, bounds, detail, folder, archive and empty search self-tests pass against a populated local library and an empty fixture database.
- Missing-library self-test reports a recoverable error.
- Native window checks cover center selection, MENU back, keyboard navigation, circular wheel dragging, settings, 3D rotation and front-view reset.
- Accessibility exposes the current selection, search field and toolbar controls.
- Task links use the route confirmed in the installed Codex app, `codex://threads/{id}`. A launch was triggered; destination-window verification was unavailable to the test tools.
- The app icon contains seven valid PNG chunks in an ICNS container.

Not tested on hardware: Intel Macs, macOS 14/15. Cloud/remote library synchronization is not implemented. No user thread database or credentials are included in the repository or release.

编译、模型结构、自测和真实窗口操作已检查。当前测试不等于所有 macOS 版本的兼容性保证，也不包含云端同步。Blender 文件中建模控制台遗留的本机用户名路径已替换为占位路径，模型几何不变。
