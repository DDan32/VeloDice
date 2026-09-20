# 🎲 VeloDice 騎跡

> **為自行車愛好者打造的現代化單車路線規劃、即時碼錶與 3D 軌跡社群分享 iOS App**

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg?style=flat&logo=apple)](https://developer.apple.com)


---

## 📱 關於 VeloDice 騎跡 (About)

**VeloDice 騎跡** 是一款專為公路車、登山車與城市單車騎士量身定制的專業騎乘伴侶。從行前的**多站點路線規劃**、**沿線補給站智慧搜尋**，到騎乘時的**專業 HUD 競速碼錶**與**藍牙感測器連線**，再到騎乘後的 **Relive 風格 3D 衛星飛行重播** 與 **Instagram 去背成績卡片**，VeloDice 帶給您一站式的極致騎乘體驗。

---

## ✨ 核心功能 (Features)

### 🗺️ 1. 地圖導航與路線規劃 (Route Planning & Navigation)
- **多停靠站靈活規劃**：支援起點、終點以及任意中途停靠點的新增、拖曳排序與刪除，空間精簡設計釋放最大地圖視野。
- **互動式海拔坡度剖面圖 (Elevation Profile)**：即時視覺化路線爬升、下降、距離與平均坡度，支援台灣全島真實地理高程備援。
- **沿途補給站智慧檢索 (Smart Supply Finder)**：
  - 每隔 5km / 10km 自動沿線採樣，深度搜尋周邊 1200 公尺內的 **便利商店（7-Eleven、全家）、加油站、自行車店**。
  - **Top 5 便捷補給推薦**：結合騎士即時位置，智慧推薦最近的超商，並在地圖上以原生高效 Marker 標繪。
- **GPX 雙向整合**：
  - **匯入 GPX**：相容 Strava、Komoot、Garmin 等匯出的 GPX 路線檔，自動解析爬升並同步搜尋沿線補給點。
  - **匯出 GPX**：將在 App 內自訂規劃的路線一鍵生成標準 GPX 檔案，輕鬆分享給車友或車錶設備。
- **全景視野自適應 (Auto Zoom Fit)**：載入路線自動平滑縮放聚焦完整路徑。

---

### ⚡ 2. 專業級即時運動記錄 (Live HUD Dashboard)
- **全方位數據監控**：即時顯示瞬時速度、平均時速、最高極速、行駛里程、累計爬升、實時坡度（%）與運動時間。
- **碼錶級防漂移閘門**：
  - GPS 精度過濾門檻（排除室內或隧道弱訊號漂移）。
  - 單車極速防護（自動剔除 >120 km/h 瞬移跳點）。
  - 原地靜止與停等紅綠燈智慧偵測，自動零時速判定。
- **藍牙運動感測器 (BLE Sensors)**：
  - 原生支援標準藍牙 GATT 協定：**心率帶 (Heart Rate Service `0x180D`)**、**踏頻/速度感測器 (CSC Service `0x1816`)** 以及 **單車功率計 (Cycling Power Service `0x1818`)**。
  - **斷線自動重連記憶 (Auto-Reconnect Memory)**：記錄配對之感測器周邊 UUID，下次騎行出發時自動秒級靜默重連，無需手動繁瑣設定。
  - 相容市售主流品牌（Garmin、Stages、Magene 邁金、4iiii、Wahoo、SRAM AXS、Shimano、Polar 等）。
  - **3 秒滑行自動歸零保護 (Auto-Zero Watchdog)**：停止踩踏滑行時自動歸零踏頻與功率數值。
- **動態導航與偏離重算 (Dynamic Off-Route & Heading Cone)**：
  - 地圖呈現 Google Maps 等級之**即時方位角航向錐形指示**（Heading Cone），精確反映騎士當下面對的方向。
  - 即時監測與規劃路線之幾何垂直距，偏離路線 >80 公尺自動提示並支援一鍵/自動重新導航。
  - 沿途補給站點選時提供智慧確認對話框，自動分析行進進度並以最順暢順序插入中途停靠點，完全保留既有起訖點。
- **AI 完賽預測與動態時間軸天氣 (AI ETA & Dynamic Timeline Weather)**：
  - 根據當前滾動平均時速、路段剩餘爬升與疲勞係數動態預估抵達時間。
  - 提供目前位置即時天氣以及沿途未來 +30 分鐘、+1 小時、+2 小時及預計完賽時之動態天氣預報。
- **里程碑成就與分段提醒 (Milestones & Segments)**：每 5km / 10km 自動分段記錄與爬坡點提醒。
- **運動結束完整摘要**：支援自訂活動名稱、備忘筆記、單車類型分類與照片上傳保存。

---

### 🎥 3. Relive 風格 3D 衛星飛行重播 (3D Relive Playback)
- **3D 衛星實景 / Apple 標準雙地圖風格自由切換**：可隨時於 3D 擬真衛星實景與清晰簡潔之 Apple 標準向量地圖間無縫切換。
- **速度自適應阻尼與前瞻平滑防抖演算法**：針對 2x、3x、8x 等高速回放採用動態角度補間與視角前瞻平滑，徹底消除運鏡抖動。
- **動態相機跟隨與全景模式**：自由切換「無人機跟隨視角」與「高空全景鳥瞰視角」。
- **靈活播放控制**：支援播放、暫停、1x / 2x / 4x / 8x 多倍速播放與進度條即時拖曳。
- **高幀率渲染優化**：軌跡幾何動態抽稀演算法，降低 GPU 負擔，流暢省電。

---

### 🎨 4. Instagram 限時動態去背卡片 (Transparent Share Card)
- **真比例路線剪影 (True-Aspect-Ratio Projection)**：
  - 考量地球緯度余弦係數（`cos(midLat)`），路線剪影 100% 原汁原味還原真實形狀，絕無長寬扭曲擠壓。
- **半透明磨砂玻璃質感**：專為 Instagram Story、Threads、Facebook 設計的現代極簡成績卡。
- **一鍵直享 IG**：支援 UIPasteboard 原生背景與貼圖深連結協定，自動喚起 Instagram 限時動態編輯器，未安裝時自動備援叫起系統分享面版。

---

### 📂 5. 本地運動歷史紀錄 (Activity Store)
- **隱私安全，純本地儲存**：騎乘紀錄經由 JSON / Codable 儲存於使用者設備，無個資洩露風險，支援無網路完全離線運作。
- **一鍵回放與再戰導航**：過往騎乘紀錄可隨時調閱高程數據、啟動 3D 飛行重播，或一鍵「載入至地圖導航」再次挑戰。

---

## 🛠️ 技術架構 (Tech Stack)

| 領域 | 使用技術 |
| :--- | :--- |
| **開發語言** | Swift 5.9+ / Swift Concurrency (async/await, Actor) |
| **使用者介面** | SwiftUI, NavigationStack, MapContentBuilder |
| **地圖服務** | Apple MapKit (`Map`, `MapPolyline`, `Marker`, `MKLocalSearch`, `MKDirections`) |
| **定位與地理計算** | CoreLocation (`CLLocationManagerDelegate`, 距離/坡度計算) |
| **無線感測通訊** | CoreBluetooth (`CBCentralManager`, `CBPeripheralDelegate`, GATT CSC & Heart Rate) |
| **高程與航向演算法** | 地球大圓航線方位角演算法 (Haversine & Bearing), 台灣地理高程估算器 |
| **圖形與分享** | SwiftUI `Canvas`, `Shape`, `ImageRenderer`, `UIPasteboard` Instagram URL Schemes |
| **資料持久化** | 本地檔案系統沙盒 (App Sandbox), JSON Codable, XML GPX Parser & Exporter |

---

## 🚀 快速開始 (Getting Started)

### 先決條件 (Prerequisites)
- **macOS**：macOS Sonoma (14.0) 或更新版本
- **Xcode**：Xcode 15.0 或更新版本
- **執行目標設備**：iOS 17.0+ (iPhone) 或 macOS 14.0+ (Mac Catalyst)
- **實體機測試建議**：BLE 感測器與 GPS 背景記錄功能建議於 iPhone 實體機進行測試

### 安裝與運行 (Installation)

1. **複製專案庫 (Clone the repository)**：
   ```bash
   git clone https://github.com/DDan32/VeloDice.git
   cd VeloDice
   ```

2. **使用 Xcode 開啟專案**：
   ```bash
   open "Untitled Project.xcodeproj" # 或於 Xcode 中打開專案資料夾
   ```

3. **配置 Signing & Capabilities**：
   - 於專案 Target 中設定您的 Apple 開發者 Team。
   - 確保已啟用 **Location When In Use / Always** 與 **Bluetooth Always** 權限。

4. **編譯並執行 (Build & Run)**：
   - 選擇 iPhone 模擬器或連接實體 iPhone。
   - 按下 `Cmd + R` 即可開始使用！

---
