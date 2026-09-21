# 🎲 VeloDice 騎跡

> **為自行車愛好者打造的現代化單車路線規劃、即時碼錶、3D 軌跡與社群分享 iOS App**  
> *A Modern Cycling Navigation, Real-time HUD, 3D Relive Playback & Social Sharing iOS App.*

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg?style=flat&logo=apple)](https://developer.apple.com)
[![Language](https://img.shields.io/badge/Language-繁體中文%20%7C%20English-green.svg?style=flat)](https://github.com/DDan32/VeloDice)
[![License](https://img.shields.io/badge/License-MIT-purple.svg?style=flat)](LICENSE)

---

## 📱 關於 VeloDice 騎跡 (About VeloDice)

**VeloDice 騎跡** 是一款專為公路車、登山車與城市單車騎士量身定制的專業騎乘伴侶。  
其靈感源自單車（**Velo**）與隨機探索骰子（**Dice**）的結合，讓騎士在熟悉生活圈中隨時發掘新路線！

從出發前的 **「🎲 命運單車骰」30km 隨機熱門路線探索**、**多停靠站路網規劃**、**沿線補給站智慧快搜**，到騎乘時的 **HUD 競速碼錶**、**藍牙感測器連線（心率/踏頻/功率）**、**Google Maps 等級即時航向錐**，再到騎乘後的 **個人專屬頭像連動 3D 衛星飛行重播**、**Strava 等級生涯榮譽榜/路段最佳 (PR)** 與 **Instagram 穿透式去背成績分享卡片**，VeloDice 帶給您一站式的極致單車體驗。

---

## ✨ 最新亮點功能 (Highlights)

### 🎲 1. 命運單車骰：距離 30 公里內熱門路線隨機探索 (VeloDice Lucky Roll)
- **專屬主畫面懸浮單車骰**：位於地圖右下角的漸層夜光按鈕，隨手一按即刻召喚命運隨機路線。
- **嚴格篩選距離目前位置 30 公里以內**：
  - 以騎士當前 GPS 座標為基準，自動計算並篩選 **30 km 範圍內** 的熱門單車路線（路線長短不限，從短程休閒到中長程山道皆涵蓋）。
  - 精選台灣北部、中部、南部與東部著名單車路廊（如淡水金色水岸、大稻埕水岸、風櫃嘴朝聖爬坡、中社路、貓空、觀音山、八里左岸、高美濕地、日月潭環潭、139 縣道、旗津環島、冬山河等）。
  - **全球 Apple Maps 動態支援**：若身處離島或海外，系統將自動透過 `MKLocalSearch` 動態探索周遭 30km 內的自行車道與自然名勝。
- **逼真 3D 擲骰動畫與重度觸覺回饋**：骰子高速旋轉、點數隨機切換與縮放回彈，體驗擲骰樂趣。
- **豐富資訊卡片與微縮地圖**：提供主題類別（河濱水岸、山道爬坡、海風巡航、人文老街等）、預估里程、預估爬升、預估騎時、難易度星級、特色標籤與即時方位微縮地圖。
- **一鍵自動導航**：點擊「確認導航至此路線 🚀」，系統自動將起點設為目前位置，立即啟動真實路網導航引擎！

### 🌐 2. 雙語多國語言即時切換 (Dynamic Language Switcher)
- **支援語言**：🇹🇼 **繁體中文 (Traditional Chinese)** 與 🇺🇸 **English (英文)**。
- **無縫即時切換**：整合專屬 `AppLanguageManager` 與 SwiftUI 響應式語系注入，**點擊切換後全 App 介面文字即時更新，無需重啟 App**。
- **隨手可及的切換入口**：
  - 「我的活動」騎士橫幅頂端設有快速切換膠囊選單。
  - 「編輯騎士個人檔案」中設有直觀語系選擇器。
  - 「命運單車骰」與「停靠站規劃」面板中亦提供獨立語系切換鈕。

---

## 🚴 完整核心功能 (Core Features)

### 🗺️ 3. 地圖導航與智慧路線規劃 (Route Planning & Navigation)
- **多停靠站靈活規劃**：支援起點、終點以及任意中途停靠點的新增、拖曳排序與刪除，空間精簡設計釋放最大地圖視野。
- **防呆去重機制**：重新輸入終點時自動清理多餘重複站點，確保路網計算精確無誤。
- **互動式海拔坡度剖面圖 (Elevation Profile)**：即時視覺化路線爬升、下降、距離與平均坡度，支援台灣全島真實地理高程備援。
- **沿途補給站智慧檢索 (Smart Supply Finder)**：
  - 每隔 5km / 10km 自動沿線採樣，深度搜尋周邊 1200 公尺內的 **便利商店（7-Eleven、全家）、加油站、單車店**。
  - **Top 5 便捷補給推薦**：結合騎士即時位置，智慧推薦最近的超商，並在地圖上以原生高效 Marker 標繪。
- **GPX 雙向整合**：
  - **匯入 GPX**：相容 Strava、Komoot、Garmin 等匯出的 GPX 路線檔，自動解析爬升並同步搜尋沿線補給點。
  - **匯出 GPX**：將在 App 內自訂規劃的路線一鍵生成標準 GPX 檔案，輕鬆分享給車友或車錶設備。
- **全景視野自適應 (Auto Zoom Fit)**：載入路線自動平滑縮放聚焦完整路徑。

---

### ⚡ 4. 專業級即時運動記錄 (Live HUD Dashboard)
- **全方位數據監控**：即時顯示瞬時速度、平均時速、最高極速、行駛里程、累計爬升、實時坡度（%）與運動時間。
- **碼錶級防漂移閥門**：
  - GPS 精度過濾門檻（排除室內或隧道弱訊號漂移）。
  - 單車極速保護（自動剔除 >120 km/h 瞬移跳點）。
  - 原地靜止與停等紅綠燈智慧偵測，自動零時速判定與自動暫停機制。
- **藍牙運動感測器 (BLE Sensors)**：
  - 原生支援標準藍牙 GATT 協定：**心率帶 (Heart Rate Service `0x180D`)**、**踏頻/速度感測器 (CSC Service `0x1816`)** 以及 **單車功率計 (Cycling Power Service `0x1818`)**。
  - **斷線自動重連記憶 (Auto-Reconnect Memory)**：記錄配對之感測器周邊 UUID，下次騎行出發時自動秒級靜默重連。
  - 相容市售主流品牌（Garmin、Stages、Magene 邁金、4iiii、Wahoo、SRAM AXS、Shimano、Polar 等）。
  - **3 秒滑行自動歸零保護 (Auto-Zero Watchdog)**：停止踩踏滑行時自動歸零踏頻與功率數值。
- **動態導航與偏離重算 (Dynamic Off-Route & Heading Cone)**：
  - 地圖呈現 Google Maps 等級之**即時方位角航向錐形指示**（Heading Cone），精確反映騎士當下面對的方向。
  - 即時監測與規劃路線之幾何垂直距，偏離路線 >80 公尺自動提示並支援一鍵重新導航。
- **AI 完賽預測與動態時間軸天氣 (AI ETA & Dynamic Timeline Weather)**：
  - 根據當前滾動平均時速、路段剩餘爬升與疲勞係數動態預估抵達時間。
  - 提供目前位置即時天氣以及沿途未來動態天氣預報。

---

### 🎥 5. Relive 風格 3D 衛星飛行重播 (3D Relive Playback)
- **騎士專屬頭像連動**：
  - 騎乘者個人檔案設定的專屬相片頭像自動轉換為優雅小圓標，第一人稱貼地跟隨！
  - 改善鏡頭聚焦演算，重播全程牢牢鎖定騎乘者中心位置。
- **3D 衛星實景 / Apple 標準雙地圖風格自由切換**：隨時於 3D 模擬衛星與清晰標準向量地圖間無縫切換。
- **速度自適應阻尼與前瞻平滑防抖演算法**：針對 1x / 2x / 4x / 8x 等多倍速回放採用動態角度補間與視角前瞻平滑，徹底消除運鏡抖動。
- **動態相機跟隨與全景模式**：自由切換「無人機跟隨視角」與「高空全景鳥瞰視角」。

---

### 🎨 6. Instagram 限動去背分享卡片 (Transparent Share Card)
- **真比例路線剪影 (True-Aspect-Ratio Projection)**：
  - 考量地球緯度餘弦係數（`cos(midLat)`），路線剪影 100% 原汁原味還原真實形狀，絕無長寬扭曲擠壓。
- **多元分享模式**：
  - **精簡數據模式**：僅保留路線剪影與精選數據（距離、爬升、均速），隱藏日期與多餘文字，畫面乾淨俐落。
  - **透明卡片模式**：半透明磨砂玻璃質感，專為 Instagram Story、Threads 設計。
- **一鍵直享 IG**：原生喚起 Instagram 限時動態編輯器，未安裝時自動備援叫起系統分享面板。

---

### 🏆 7. 本地運動歷史、個人檔案與榮譽榜 (Activity Store & Profile)
- **騎士個人檔案 (Rider Profile)**：自訂暱稱、騎乘座右銘、主要愛車與個人相片頭像。
- **Strava 風格生涯榮譽榜 (Career Records)**：自動統計歷史累計騎行次數、總里程、總爬升、最長騎行距離、最快極速等終生成就。
- **路段最佳成績 (Segment PR)**：智慧辨識經典路線與自訂路段，精準截斷計時並記錄個人歷史最佳成績。
- **90 天垃圾桶軟刪除機制 (Trash Bin)**：誤刪活動與路段提供 90 天安全期，隨時一鍵復原或立即清空。
- **隱私安全，純本地儲存**：騎乘記錄純本地沙盒保存，無個資洩露風險，支援完全離線運作。

---

## 🛠️ 技術架構 (Tech Stack)

| 領域 | 使用技術 |
| :--- | :--- |
| **開發語言** | Swift 5.9+ / Swift Concurrency (`async/await`, `@MainActor`, `Actor`) |
| **使用者介面** | SwiftUI, NavigationStack, MapKit for SwiftUI, Charts |
| **語系國際化** | 專屬 `AppLanguageManager`，支援繁體中文（zh-Hant）與英文（en）即時動態切換 |
| **地圖服務** | Apple MapKit (`Map`, `MapPolyline`, `Marker`, `MKLocalSearch`, `MKDirections`) |
| **定位與地理計算** | CoreLocation (`CLLocationManagerDelegate`, 距離/坡度/航向方位角計算) |
| **無線感測通訊** | CoreBluetooth (`CBCentralManager`, `CBPeripheralDelegate`, GATT CSC, HRM & Power) |
| **高程與地理運算** | 地球大圓航線方位角演算法 (Haversine & Bearing), 台灣地理高程估算器 |
| **圖形與分享** | SwiftUI `Canvas`, `Shape`, `ImageRenderer`, `UIPasteboard` Instagram URL Schemes |
| **資料持久化** | 本地檔案系統沙盒 (App Sandbox), JSON Codable, XML GPX Parser & Exporter |

---

## 🚀 快速開始 (Getting Started)

### 先決條件 (Prerequisites)
- **macOS**：macOS Sonoma (14.0) 或更高版本
- **Xcode**：Xcode 15.0 或更高版本
- **目標設備**：iOS 17.0+ (iPhone) 或 macOS 14.0+ (Mac Catalyst)
- **實體機建議**：BLE 感測器與 GPS 背景記錄功能建議於 iPhone 實體機進行測試

### 安裝與運行 (Installation)

1. **複製專案庫 (Clone the repository)**：
   ```bash
   git clone https://github.com/DDan32/VeloDice.git
   cd VeloDice
   ```

2. **使用 Xcode 開啟專案**：
   ```bash
   open VeloDice.xcodeproj
   ```

3. **配置 Signing & Capabilities**：
   - 於專案 Target 中設定您的 Apple 開發者 Team。
   - 確保已啟用 **Location When In Use / Always** 與 **Bluetooth Always** 權限。

4. **編譯並執行 (Build & Run)**：
   - 選擇 iPhone 模擬器或連接實體 iPhone。
   - 按下 `Cmd + R` 即可開始享受 VeloDice！

---

## 📄 授權條款 (License)

本專案採用 [MIT License](LICENSE) 授權。歡迎自由閱讀、學習、改進與貢獻代碼！🚴💨🎲
