# FF14 金碟 G.A.T.E. 自動循環（SND）

`GATE_AutoLoop.lua`：每 20 分鐘（地球時間 :00 / :20 / :40）自動找「活動解說員」詢問目前的 G.A.T.E.，傳送到現場並報名。進場後由 [Saucy](https://github.com/PunishXIV/Saucy) 自動玩。限繁中客戶端。

## 需要
- SomethingNeedDoing
- vnavmesh
- Saucy：**台服插件庫的 Saucy（cycleapple v1.4.2.9）沒有這些 G.A.T.E. 的自動化**，暴風倖存者、快刀斬魔只會在畫面上標示，也沒有空軍裝甲。要用加了自動化的修改版（本機編譯的開發插件，見下方「Saucy 修改版」）
- BossMod：快刀斬魔的閃避要用到
- TextAdvance：不需要。腳本會自己點掉對話框（`/click Talk Click`，點不掉就按確認鍵小鍵盤 0），開著也沒關係
- AutoRetainer（選用）：兩場之間收雇員

## 支援的 G.A.T.E.
| G.A.T.E. | 設定 | 預設 |
|---|---|---|
| 必中一閃快刀斬魔 | `JoinSlice` | 開 |
| 暴風倖存者 | `JoinWind` | 開 |
| 空軍裝甲駕駛員 | `JoinAirForce` | 開 |
| 登高跳跳樂大挑戰 | `JoinLeap` | 關（Saucy 不支援） |
| 搶救小雛鳥大作戰 | `JoinCliff` | 關（Saucy 不支援） |

`MaxGates` 是參加幾場後停止，0 = 無限循環。

## 收雇員（AutoRetainer）
`Retainers` 開著（預設）而且有載入 AutoRetainer 時，在兩場中間的空檔會自動收雇員：
- 每 30 秒問一次 AutoRetainer 有沒有探險回來的雇員
- 離下一場還有 5 分鐘以上（`PrepareSeconds` + 240 秒），而且不在快刀斬魔、暴風倖存者的場上（報名後 12 分鐘內），才會去
- 走到乙太之光廣場的傳喚鈴，打開雇員清單後下 `/ays e`，交給 AutoRetainer 處理（收探險、重派等照你在 AutoRetainer 的設定），處理完會自己關掉清單

## Saucy 修改版
以台服 Saucy（cycleapple/Saucy `api13-tw`）為基礎，從官方 PunishXIV/Saucy 移植：
- 空軍裝甲駕駛員：自動射擊。射擊函式的特徵碼和欄位位移是依台服客戶端（2026.09.14）重新核對的，動手前會先檢查，對不上就停用
- 暴風倖存者：用 vnavmesh 自動走到安全點
- 必中一閃快刀斬魔：場上時把 BossMod 的預設切到「VBM AI」，由 BossMod 的快刀斬魔模組閃避，離場換回原本的預設

安裝：`/xlsettings` → 測試版 → 開發插件位置加入編譯出來的 `Saucy.dll`，停用原本的 Saucy，再啟用開發版。在 Saucy 的「其他遊戲」分頁勾選三個模組和自動移動／閃避。

## 狀態
還沒在遊戲裡實測過。每一步都會用 `[GATE]` 開頭印在聊天欄，有問題就看這些訊息。
