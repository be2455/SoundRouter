# 參與開發

*[English](CONTRIBUTING.md) · 繁體中文*

## 先讀這段：沒聲音多半是權限問題

Core Audio 的 process tap 需要系統音訊擷取授權。**沒有授權時，`AudioHardwareCreateProcessTap` 照樣成功、IOProc 照樣全速執行、buffer 佈局也完全正確——但每一個樣本都是零。** 全程沒有任何地方會報錯。

所以第一次建置完、設了路由卻聽不到聲音，那幾乎不是你改壞的。先確認這件事：

1. 用 `./Packaging/build-app.sh` 建置，啟動 `build/SoundRouter.app`。
2. 隨便改一個 App 的輸出裝置，macOS 應該會跳出授權提示，按允許。
3. 沒跳提示的話，到「系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製」檢查。

建置預設是 **ad-hoc 簽章**，簽章雜湊每次重建都會變，macOS 可能把每個版本當成新 App 而要求重新授權。要避免：

1. 鑰匙圈存取 → 憑證輔助程式 → 建立憑證⋯
2. 名稱隨意，識別類型選「自我簽署根憑證」，憑證類型選「程式碼簽署」。
3. 用 `CODESIGN_IDENTITY="你的憑證名稱" ./Packaging/build-app.sh` 建置。

## 環境設定

```bash
git clone https://github.com/dws741119/SoundRouter.git
cd SoundRouter
swift build          # 函式庫、CLI 與 App
swift test           # 只測不依賴硬體的邏輯
./Packaging/build-app.sh
```

需要 macOS 15 以上與 Swift 6。零外部相依，離線可建置。

`swift build` 只編譯你自己的架構，開發時用這個比較快；`build-app.sh` 會建 universal
（arm64 + x86_64），時間大約是兩倍。

## 除錯

CLI 是看清楚音訊層到底在做什麼的最快方式。它需要 bundle 身分才拿得到授權，所以要跑包過的版本：

```bash
open -n -a "$PWD/build/AudioRouterProbe.app" --args \
  --log /tmp/probe.log route Spotify --to 外接喇叭 --meter --debug --seconds 10
cat /tmp/probe.log
```

`--debug` 會印出 tap 的格式、aggregate 裝置的 buffer 佈局、IOProc 呼叫次數，以及**套用音量之前**從 tap 讀到的原始峰值。最後那個數字是關鍵——它能區分「tap 給的就是靜音」和「我們算錯了」。

`--keep-original` 會在不靜音來源 App 的情況下建 tap，可以一邊正常聆聽一邊量測。

選單列 App 沒有 stdout，所以每次 refresh 會把它看到的裝置與播放源覆寫到 `~/Library/Logs/SoundRouter-status.txt`。畫面不對時先看這個檔案，能立刻分辨是資料問題還是版面問題。

## 動渲染路徑之前

`RouteEngine.render` 跑在即時音訊執行緒上。在它裡面：

- 不配置記憶體
- 不取鎖
- 不呼叫可能配置記憶體的 Objective-C 或 Swift runtime（不要 `String`、不要陣列、不要會逃逸的閉包）

音訊執行中 UI 仍可調整的參數（音量、靜音、平衡）放在一塊一次配置好的記憶體裡，主執行緒寫、音訊執行緒讀。這是刻意的設計。要新增參數請加進那個 struct，不要改用鎖。

## 測試

`swift test` 只涵蓋不需要音訊硬體的邏輯，主要是把 helper 與 XPC 行程併回所屬 App 的分組規則。那個分組決定了「路由某個 App 到底抓不抓得到聲音」，值得用測試守住。

tap 與 aggregate **刻意不測**：它們需要真實裝置與已授權的權限，在 CI 上跑只會得到假的綠燈。要加測試的話建議照同樣的切法——把純粹的判斷邏輯抽出來測，讓 Core Audio 的呼叫留在邊界。

CI 會在 macOS runner 上跑 `swift build` 與 `swift test`，無法驗證任何實際的音訊行為。

## 程式碼風格

跟著周圍的程式碼寫。這個專案有幾個特別重要的慣例：

- **註解寫「為什麼」，不寫「做什麼」。** 這份程式碼打交道的 API 有好幾個沒寫在文件上、也猜不到的行為——沒授權的 tap 是靜音而非錯誤、HAL 從來不通知 `kAudioProcessPropertyIsRunningOutput`、`ScrollView` 在 `MenuBarExtra` 裡沒有固有高度。你如果發現這類事情，請寫在依賴它的那段程式碼旁邊。這些註解是這個倉庫最有價值的部分。
- **讀 Core Audio 屬性時一律指明型別**：`try obj.read(selector, as: UInt32.self)`。不寫的話 `try?` 可能把泛型推導成 `Optional<UInt32>`，算出的大小多一個 byte，被 Core Audio 拒絕，然後錯誤又被 `try?` 吞成 `nil`。`read` 在 debug 版會對這種情況斷言。
- 現有註解是繁體中文。新程式碼寫英文也可以，目前混用可接受，也歡迎協助翻譯。

## Pull request

- 說明你測了什麼、在什麼硬體上測的。「在 macOS 26 / Apple Silicon 上把 Spotify 導到 USB DAC 測過」比「可以動」有用太多。
- 音訊的問題常常跟硬體綁在一起。你的裝置的取樣率、聲道數、交錯方式都有影響，回報問題時請一併附上。
- 不要把無關的改動混進同一個 diff。

## 想找事情做的話，這些是已知缺口

- EQ／AudioUnit 效果鏈——掛點在 `RouteEngine.render` 寫入 output buffer 之前。
- 一個 App 同時分流到多個輸出裝置。
- AirPlay：AirPlay 目標會以 Core Audio 裝置出現，但它能不能當 aggregate 的 sub-device 尚未實測。
- 在地化——所有介面字串都寫死繁體中文。
- Intel Mac 完全沒有驗證過。
