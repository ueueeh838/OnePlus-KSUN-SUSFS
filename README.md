# ⭐⭐⭐ Star This Project ⭐⭐⭐

如果您觉得这个项目对您有帮助，请给我们一个 star / 进行赞助！您的支持是我们持续改进的动力

<img width="250" height="250" alt="image" src="https://github.com/user-attachments/assets/55acad97-8fe6-4de7-b9ce-90da9552a212" />

## OnePlus Kernel 开源地址

[![OnePlus Repository](https://img.shields.io/badge/OnePlus-Repository-red)](https://github.com/Xiaomichael/kernel_manifest)

## 设备支持

> [!TIP]
> **一加6/6系列用户**请移步至：[专用仓库](https://github.com/Xiaomichael/oneplus_6.6_devices)

## 使用指南

### 配置文件说明

以**一加12**为例：
- 无后缀：Android 15
- `_u` 后缀：Android 14
- `_t` 后缀：Android 13

![配置文件示例](https://github.com/user-attachments/assets/88f6940b-4b2c-462f-b8fa-3d9dd2f2faec)

### 分支选择

1. 点击 `Branches` 切换处理器分支
2. 选择适合您设备的配置

<img width="318.8" height="500" alt="{2737F086-DBF5-4F52-B98E-2475D8CD4A42}" src="https://github.com/user-attachments/assets/483a4abd-1c09-4421-aa31-a4f97cb1311f" />

### 如何查看处理器代号

![处理器代号查看方法](https://github.com/user-attachments/assets/fc217103-24ef-45fa-a7e1-f13cfd64f771)
在对应分支下面有写，如果出现的是`using make build`就不用管，默认即可，不影响编译

## 一些开关建议

- **kpm**：建议禁用以减少电量消耗
- **lz4kd**：
  - 6.1系列内核：建议关闭以获得更好的 `lz4 + zstd`
  - 其他内核版本：建议保持开启
- **代理优化**: 骁龙系可以开，联发科芯片勿开，否则出现恶性Bug！
- **BBG防格机**: 当然推荐开启，看名字就知道是干啥的

## 运行时配置示例

<img width="188.5" height="418.5" alt="{1D096FF8-ADC8-44FB-ABB0-B90E6BFD997D}" src="https://github.com/user-attachments/assets/2868dd1b-cb38-48fc-8041-490c5e700baf" />
